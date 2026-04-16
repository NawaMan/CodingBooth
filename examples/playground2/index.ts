const server = Bun.serve({
  port: 3000,
  fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/") {
      return new Response(
        `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Math Problem</title>
  <style>
    body { font-family: sans-serif; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: #f0f0f0; }
    .card { background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); text-align: center; }
    h1 { margin-top: 0; }
    .problem { font-size: 2rem; margin: 1.5rem 0; }
    input { font-size: 1.5rem; padding: 0.5rem; width: 100px; text-align: center; border: 2px solid #ccc; border-radius: 4px; }
    button { font-size: 1.2rem; padding: 0.5rem 1.5rem; margin-left: 0.5rem; background: #4CAF50; color: white; border: none; border-radius: 4px; cursor: pointer; }
    button:hover { background: #45a049; }
    #result { margin-top: 1rem; font-size: 1.2rem; min-height: 1.5em; }
    .correct { color: green; }
    .wrong { color: red; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Solve the Problem</h1>
    <div class="problem" id="problem"></div>
    <div>
      <input type="number" id="answer" placeholder="?" autofocus />
      <button onclick="check()">Submit</button>
    </div>
    <div id="result"></div>
    <button onclick="newProblem()" style="margin-top:1rem;background:#2196F3;">New Problem</button>
  </div>
  <script>
    let correctAnswer;

    function newProblem() {
      const a = Math.floor(Math.random() * 50) + 1;
      const b = Math.floor(Math.random() * 50) + 1;
      const ops = ['+', '-', '*'];
      const op = ops[Math.floor(Math.random() * ops.length)];
      correctAnswer = op === '+' ? a + b : op === '-' ? a - b : a * b;
      document.getElementById('problem').textContent = a + ' ' + op + ' ' + b + ' = ?';
      document.getElementById('answer').value = '';
      document.getElementById('result').textContent = '';
      document.getElementById('answer').focus();
    }

    function check() {
      const input = document.getElementById('answer').value;
      if (input === '') return;
      const res = document.getElementById('result');
      if (parseInt(input) === correctAnswer) {
        res.textContent = 'Correct!';
        res.className = 'correct';
      } else {
        res.textContent = 'Wrong — the answer is ' + correctAnswer;
        res.className = 'wrong';
      }
    }

    document.getElementById('answer').addEventListener('keydown', e => { if (e.key === 'Enter') check(); });
    newProblem();
  </script>
</body>
</html>`,
        { headers: { "Content-Type": "text/html" } }
      );
    }

    return new Response("Not Found", { status: 404 });
  },
});

console.log(`Server running at http://localhost:${server.port}`);
