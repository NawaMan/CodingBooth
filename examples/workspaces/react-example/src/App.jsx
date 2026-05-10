import { useState } from 'react'

export default function App() {
  const [count, setCount] = useState(0)
  return (
    <main style={{ fontFamily: 'system-ui', padding: '2rem' }}>
      <h1>Hello from React in CodingBooth!</h1>
      <p>Click the button to confirm React state works:</p>
      <button onClick={() => setCount((c) => c + 1)}>
        Clicked {count} time{count === 1 ? '' : 's'}
      </button>
    </main>
  )
}
