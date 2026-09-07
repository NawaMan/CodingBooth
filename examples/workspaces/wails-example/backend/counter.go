package backend

import "sync"

// Counter is the Go service the frontend calls. The number lives here, not in JS.
type Counter struct {
	mu    sync.Mutex
	value int
}

func (c *Counter) Value() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.value
}

func (c *Counter) Increment() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.value++
	return c.value
}

func (c *Counter) Reset() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.value = 0
	return c.value
}
