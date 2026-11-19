import { useEffect, useState } from 'react'

export default function App() {
  const [items, setItems] = useState([])
  useEffect(() => {
    fetch('http://localhost:3000/api/items')
      .then((r) => r.json())
      .then(setItems)
      .catch(() => setItems([{ _id: 'err', message: 'API not reachable yet' }]))
  }, [])
  return (
    <main style={{ fontFamily: 'system-ui', padding: '2rem' }}>
      <h1>Hello from MERN in CodingBooth!</h1>
      <p>Items from the Express API (which reads MongoDB):</p>
      <ul>
        {items.map((it) => (
          <li key={it._id}>{it.message}</li>
        ))}
      </ul>
    </main>
  )
}
