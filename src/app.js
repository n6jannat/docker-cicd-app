const express = require('express');

const startedAt = new Date();

function createApp() {
  const app = express();
  app.use(express.json());

  app.get('/', (req, res) => {
    res.json({
      message: 'Hello from docker-cicd-app!',
      environment: process.env.APP_ENV || 'development',
      version: process.env.APP_VERSION || 'dev',
    });
  });

  // Used by Docker HEALTHCHECK and by the deploy job's smoke test.
  app.get('/health', (req, res) => {
    res.json({ status: 'ok', uptime: Math.round((Date.now() - startedAt) / 1000) });
  });

  const todos = [];
  app.get('/api/todos', (req, res) => res.json(todos));
  app.post('/api/todos', (req, res) => {
    const { title } = req.body || {};
    if (typeof title !== 'string' || !title.trim()) {
      return res.status(400).json({ error: 'title is required' });
    }
    const todo = { id: todos.length + 1, title: title.trim(), done: false };
    todos.push(todo);
    res.status(201).json(todo);
  });

  return app;
}

module.exports = { createApp };
