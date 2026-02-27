'use strict';

const express = require('express');
const fs      = require('fs');
const path    = require('path');

// ── Config ────────────────────────────────────────────────────────────────────
const PORT      = process.env.PORT || 3000;
const DATA_FILE = path.join(__dirname, 'notes.json');
const app       = express();

// ── View engine ───────────────────────────────────────────────────────────────
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(express.urlencoded({ extended: false }));  // form POSTs
app.use(express.json());                           // JSON API POSTs
app.use(express.static(path.join(__dirname, 'public')));

// ── Storage helpers ───────────────────────────────────────────────────────────

/**
 * Read notes from disk.
 * Returns { data: Note[], error: string|null }
 */
function readNotes() {
  try {
    if (!fs.existsSync(DATA_FILE)) return { data: [], error: null };
    const raw = fs.readFileSync(DATA_FILE, 'utf8').trim();
    if (!raw) return { data: [], error: null };
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error('Data file is not an array.');
    return { data: parsed, error: null };
  } catch (err) {
    console.error('[readNotes]', err.message);
    return { data: [], error: 'Could not read notes from disk.' };
  }
}

/**
 * Write notes to disk.
 * Returns { success: boolean, error: string|null }
 */
function writeNotes(notes) {
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(notes, null, 2), 'utf8');
    return { success: true, error: null };
  } catch (err) {
    console.error('[writeNotes]', err.message);
    return { success: false, error: 'Could not save note to disk.' };
  }
}

// ── Input validation ──────────────────────────────────────────────────────────
const MAX_TEXT_LENGTH = 500;

function validateNoteText(text) {
  if (text === undefined || text === null) {
    return '"text" field is required.';
  }
  const trimmed = String(text).trim();
  if (trimmed.length === 0) {
    return 'Note text must not be empty.';
  }
  if (trimmed.length > MAX_TEXT_LENGTH) {
    return `Note text must be ${MAX_TEXT_LENGTH} characters or fewer (got ${trimmed.length}).`;
  }
  return null; // valid
}

// ── Routes ────────────────────────────────────────────────────────────────────

// GET /  → render UI
app.get('/', (req, res) => {
  const { data: notes, error } = readNotes();
  res.render('index', {
    notes,
    storageError: error,
    flash: req.query.flash || null,
    flashType: req.query.flashType || 'success',
  });
});

// GET /health
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// GET /notes  → JSON API
app.get('/notes', (req, res) => {
  const { data: notes, error } = readNotes();
  if (error) return res.status(500).json({ error });
  res.status(200).json(notes);
});

// POST /notes  → accepts both HTML form and JSON
app.post('/notes', (req, res) => {
  const isHtml = req.headers['content-type']?.includes('application/x-www-form-urlencoded');

  const text = req.body?.text;
  const validationError = validateNoteText(text);

  if (validationError) {
    if (isHtml) {
      return res.redirect(
        `/?flash=${encodeURIComponent(validationError)}&flashType=error`
      );
    }
    return res.status(422).json({ error: validationError });
  }

  const { data: notes, error: readError } = readNotes();
  if (readError) {
    if (isHtml) {
      return res.redirect(
        `/?flash=${encodeURIComponent(readError)}&flashType=error`
      );
    }
    return res.status(500).json({ error: readError });
  }

  const note = {
    id:        `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
    text:      String(text).trim(),
    createdAt: new Date().toISOString(),
  };

  notes.push(note);
  const { error: writeError } = writeNotes(notes);

  if (writeError) {
    if (isHtml) {
      return res.redirect(
        `/?flash=${encodeURIComponent(writeError)}&flashType=error`
      );
    }
    return res.status(500).json({ error: writeError });
  }

  if (isHtml) {
    return res.redirect('/?flash=Note+saved+successfully&flashType=success');
  }
  res.status(201).json(note);
});

// DELETE /notes/:id  → JSON API (bonus)
app.delete('/notes/:id', (req, res) => {
  const { data: notes, error: readError } = readNotes();
  if (readError) return res.status(500).json({ error: readError });

  const index = notes.findIndex(n => n.id === req.params.id);
  if (index === -1) {
    return res.status(404).json({ error: `Note "${req.params.id}" not found.` });
  }

  notes.splice(index, 1);
  const { error: writeError } = writeNotes(notes);
  if (writeError) return res.status(500).json({ error: writeError });

  res.status(200).json({ deleted: req.params.id });
});

// ── 404 handler ───────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: `Cannot ${req.method} ${req.path}` });
});

// ── Global error handler ──────────────────────────────────────────────────────
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[GlobalError]', err);
  res.status(500).json({ error: 'An unexpected error occurred.' });
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, "0.0.0.0", () => {
  console.log(`notes-service running → http://0.0.0.0:${PORT}`);
  console.log(`Storage file          → ${DATA_FILE}`);
});
