import { exportTasks } from '../api/client';

export function ExportButton() {
  return (
    <div className="flex gap-2">
      <button
        onClick={() => exportTasks('csv')}
        className="bg-green-600 text-white px-4 py-2 rounded-md hover:bg-green-700 transition-colors text-sm"
      >
        Export CSV
      </button>
      <button
        onClick={() => exportTasks('json')}
        className="bg-purple-600 text-white px-4 py-2 rounded-md hover:bg-purple-700 transition-colors text-sm"
      >
        Export JSON
      </button>
    </div>
  );
}
