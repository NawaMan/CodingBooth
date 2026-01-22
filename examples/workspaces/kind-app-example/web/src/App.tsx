import { useState, useEffect, useCallback } from 'react';
import { Task, getTasks } from './api/client';
import { useWebSocket, TaskEvent } from './hooks/useWebSocket';
import { TaskForm } from './components/TaskForm';
import { TaskList } from './components/TaskList';
import { ExportButton } from './components/ExportButton';

function App() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchTasks = async () => {
    try {
      const data = await getTasks();
      setTasks(data);
      setError(null);
    } catch (err) {
      setError('Failed to load tasks');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchTasks();
  }, []);

  const handleWebSocketEvent = useCallback((event: TaskEvent) => {
    switch (event.type) {
      case 'task_created':
        setTasks((prev) => [event.task, ...prev]);
        break;
      case 'task_updated':
        setTasks((prev) =>
          prev.map((t) => (t.id === event.task.id ? event.task : t))
        );
        break;
      case 'task_deleted':
        setTasks((prev) => prev.filter((t) => t.id !== event.task.id));
        break;
    }
  }, []);

  useWebSocket(handleWebSocketEvent);

  const handleTaskCreated = (task: Task) => {
    // WebSocket will handle the update, but we can optimistically add it
    // Only add if not already present (WebSocket might be faster)
    setTasks((prev) => {
      if (prev.some((t) => t.id === task.id)) return prev;
      return [task, ...prev];
    });
  };

  const handleTaskUpdate = (updatedTask: Task) => {
    setTasks((prev) =>
      prev.map((t) => (t.id === updatedTask.id ? updatedTask : t))
    );
  };

  const handleTaskDelete = (id: number) => {
    setTasks((prev) => prev.filter((t) => t.id !== id));
  };

  return (
    <div className="min-h-screen bg-gray-100 py-8">
      <div className="max-w-2xl mx-auto px-4">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-3xl font-bold text-gray-900">TODO App</h1>
          <ExportButton />
        </div>

        {error && (
          <div className="bg-red-100 text-red-700 p-4 rounded-lg mb-6">
            {error}
            <button
              onClick={fetchTasks}
              className="ml-4 underline hover:no-underline"
            >
              Retry
            </button>
          </div>
        )}

        <TaskForm onTaskCreated={handleTaskCreated} />

        {isLoading ? (
          <div className="text-center py-8 text-gray-500">Loading tasks...</div>
        ) : (
          <TaskList
            tasks={tasks}
            onUpdate={handleTaskUpdate}
            onDelete={handleTaskDelete}
          />
        )}

        <div className="mt-8 text-center text-sm text-gray-500">
          <p>Real-time sync enabled via WebSocket</p>
          <p className="mt-1">Open this page in multiple tabs to see live updates</p>
        </div>
      </div>
    </div>
  );
}

export default App;
