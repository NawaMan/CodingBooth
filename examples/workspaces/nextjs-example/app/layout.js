export const metadata = {
  title: 'Next.js in CodingBooth',
}

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: 'system-ui', padding: '2rem' }}>{children}</body>
    </html>
  )
}
