import express from 'express'
import cors from 'cors'
import mongoose from 'mongoose'

const PORT = 3000
const MONGO_URI = process.env.MONGO_URI || 'mongodb://127.0.0.1:27017/mern_demo'

const itemSchema = new mongoose.Schema({ message: String }, { timestamps: true })
const Item = mongoose.model('Item', itemSchema)

async function seedIfEmpty() {
  if ((await Item.countDocuments()) === 0) {
    await Item.create({ message: 'Hello from MongoDB!' })
  }
}

await mongoose.connect(MONGO_URI)
await seedIfEmpty()

const app = express()
app.use(cors())

app.get('/api/items', async (_req, res) => {
  res.json(await Item.find().lean())
})

app.listen(PORT, '0.0.0.0', () => {
  console.log(`MERN API listening on http://localhost:${PORT}`)
})
