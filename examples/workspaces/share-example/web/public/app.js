// Front-end logic. Calls the API through the same origin (/api/...), which
// web/server.js forwards to the API server — so it works the same on
// localhost and on a shared public URL.
const $ = (id) => document.getElementById(id);

async function api(path, options = {}) {
  const res = await fetch('/api' + path, { headers: { 'Content-Type': 'application/json' }, ...options });
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || res.statusText);
  return res.status === 204 ? null : res.json();
}

async function load() {
  try {
    const notes = await api('/notes');
    $('notes').replaceChildren(...notes.slice().reverse().map(render));
    $('status').textContent = '';
  } catch (e) {
    $('status').textContent = 'Could not load notes: ' + e.message;
  }
}

function render(note) {
  const li = document.createElement('li');
  li.innerHTML = '<div class="body"><div class="text"></div><div class="meta"></div></div><button title="Delete">✕</button>';
  li.querySelector('.text').textContent = note.text;
  li.querySelector('.meta').textContent = `${note.author} · ${new Date(note.created).toLocaleString()}`;
  li.querySelector('button').onclick = async () => { await api('/notes/' + note.id, { method: 'DELETE' }); load(); };
  return li;
}

$('add').onsubmit = async (e) => {
  e.preventDefault();
  try {
    await api('/notes', { method: 'POST', body: JSON.stringify({ text: $('text').value, author: $('author').value }) });
    $('text').value = '';
    load();
  } catch (err) {
    $('status').textContent = 'Could not add: ' + err.message;
  }
};

load();
setInterval(load, 3000);   // see notes others add through the shared URL
