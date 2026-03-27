package service

import (
	"context"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"sync"
	"time"
)

const (
	callbackServerAddr = "127.0.0.1:1455"
	callbackPath       = "/auth/callback"
	callbackTTL        = 10 * time.Minute
)

// callbackResult stores the OAuth callback result
type callbackResult struct {
	Code      string
	State     string
	Error     string
	ReceivedAt time.Time
}

// CallbackStore stores OAuth callback results keyed by state
type CallbackStore struct {
	mu      sync.RWMutex
	results map[string]*callbackResult // key: state value
}

func newCallbackStore() *CallbackStore {
	s := &CallbackStore{
		results: make(map[string]*callbackResult),
	}
	go s.cleanup()
	return s
}

func (s *CallbackStore) set(state string, result *callbackResult) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.results[state] = result
}

func (s *CallbackStore) get(state string) (*callbackResult, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	r, ok := s.results[state]
	if !ok {
		return nil, false
	}
	if time.Since(r.ReceivedAt) > callbackTTL {
		return nil, false
	}
	return r, true
}

func (s *CallbackStore) delete(state string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.results, state)
}

func (s *CallbackStore) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		s.mu.Lock()
		for k, v := range s.results {
			if time.Since(v.ReceivedAt) > callbackTTL {
				delete(s.results, k)
			}
		}
		s.mu.Unlock()
	}
}

// callbackServer is a singleton local HTTP server on port 1455 to receive OAuth callbacks
type callbackServer struct {
	store    *CallbackStore
	server   *http.Server
	startOnce sync.Once
	mu       sync.Mutex
	started  bool
}

var globalCallbackServer = &callbackServer{
	store: newCallbackStore(),
}

// StartCallbackServer starts the local OAuth callback server on port 1455.
// It is safe to call multiple times; subsequent calls are no-ops if already running.
func StartCallbackServer() {
	globalCallbackServer.startOnce.Do(func() {
		mux := http.NewServeMux()
		mux.HandleFunc(callbackPath, globalCallbackServer.handleCallback)

		globalCallbackServer.server = &http.Server{
			Addr:    callbackServerAddr,
			Handler: mux,
		}

		ln, err := net.Listen("tcp", callbackServerAddr)
		if err != nil {
			slog.Warn("openai_callback_server_start_failed", "addr", callbackServerAddr, "error", err)
			return
		}
		globalCallbackServer.mu.Lock()
		globalCallbackServer.started = true
		globalCallbackServer.mu.Unlock()

		slog.Info("openai_callback_server_started", "addr", callbackServerAddr)
		go func() {
			if err := globalCallbackServer.server.Serve(ln); err != nil && err != http.ErrServerClosed {
				slog.Warn("openai_callback_server_error", "error", err)
			}
		}()
	})
}

// StopCallbackServer gracefully shuts down the callback server
func StopCallbackServer(ctx context.Context) {
	globalCallbackServer.mu.Lock()
	started := globalCallbackServer.started
	globalCallbackServer.mu.Unlock()

	if started && globalCallbackServer.server != nil {
		_ = globalCallbackServer.server.Shutdown(ctx)
	}
}

// GetCallbackStore returns the global callback store for polling
func GetCallbackStore() *CallbackStore {
	return globalCallbackServer.store
}

func (s *callbackServer) handleCallback(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	code := q.Get("code")
	state := q.Get("state")
	errParam := q.Get("error")
	errDesc := q.Get("error_description")

	result := &callbackResult{
		Code:       code,
		State:      state,
		ReceivedAt: time.Now(),
	}
	if errParam != "" {
		result.Error = fmt.Sprintf("%s: %s", errParam, errDesc)
	}

	if state != "" {
		s.store.set(state, result)
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)

	if errParam != "" {
		fmt.Fprintf(w, callbackErrorHTML, errParam, errDesc)
		return
	}

	fmt.Fprint(w, callbackSuccessHTML)
}

const callbackSuccessHTML = `<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>授权成功 - Authorization Successful</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: #f0f9f0; display: flex; align-items: center; justify-content: center;
    min-height: 100vh; padding: 20px; }
  .card { background: white; border-radius: 12px; padding: 40px; max-width: 480px;
    width: 100%; box-shadow: 0 4px 24px rgba(0,0,0,0.08); text-align: center; }
  .icon { width: 64px; height: 64px; background: #d1fae5; border-radius: 50%;
    display: flex; align-items: center; justify-content: center; margin: 0 auto 20px; }
  .icon svg { width: 36px; height: 36px; color: #10b981; }
  h1 { font-size: 22px; font-weight: 700; color: #111; margin-bottom: 8px; }
  p { color: #6b7280; font-size: 15px; line-height: 1.6; }
  .tip { margin-top: 20px; padding: 14px; background: #eff6ff; border-radius: 8px;
    color: #1d4ed8; font-size: 14px; }
</style>
</head>
<body>
<div class="card">
  <div class="icon">
    <svg fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7"/>
    </svg>
  </div>
  <h1>授权成功！</h1>
  <p>OpenAI 账号已授权，正在自动完成添加。</p>
  <div class="tip">请返回 sub2api 管理界面，账号将自动添加完成。<br>Authorization successful. Return to sub2api.</div>
</div>
</body>
</html>`

const callbackErrorHTML = `<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<title>授权失败</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: #fff5f5; display: flex; align-items: center; justify-content: center;
    min-height: 100vh; padding: 20px; }
  .card { background: white; border-radius: 12px; padding: 40px; max-width: 480px;
    width: 100%; box-shadow: 0 4px 24px rgba(0,0,0,0.08); text-align: center; }
  h1 { font-size: 20px; color: #dc2626; margin-bottom: 12px; }
  p { color: #6b7280; font-size: 14px; }
  .err { margin-top: 16px; padding: 12px; background: #fef2f2; border-radius: 8px;
    color: #991b1b; font-size: 13px; font-family: monospace; }
</style>
</head>
<body>
<div class="card">
  <h1>授权失败</h1>
  <p>OpenAI 返回了错误，请关闭此页面重试。</p>
  <div class="err">%s: %s</div>
</div>
</body>
</html>`
