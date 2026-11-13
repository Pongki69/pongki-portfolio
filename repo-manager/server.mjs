import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const host = '127.0.0.1';
const port = 4179;
const owner = 'Pongki69';
const managerDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(managerDirectory, '..');
const configPath = path.join(projectDirectory, 'portfolio-projects.json');
const iconDirectory = path.join(projectDirectory, 'assets', 'project-icons');
const pagePath = path.join(managerDirectory, 'index.html');
const scriptPath = path.join(managerDirectory, 'manager.js');
const allowedStatuses = new Set(['github', 'in-progress', 'live', 'hidden']);
let repoCache = { until: 0, repositories: null };
let saving = false;

function sendJson(response, statusCode, data) {
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff'
  });
  response.end(JSON.stringify(data));
}

function isLocalRequest(request) {
  const origin = request.headers.origin;
  return request.headers.host === `${host}:${port}` && origin === `http://${host}:${port}`;
}

async function readRequestBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 5_000_000) throw new Error('The submitted project list is too large.');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

async function git(args) {
  const response = await fetch('http://127.0.0.1:4181/api/git', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: `http://${host}:${port}` },
    body: JSON.stringify({ args }),
    signal: AbortSignal.timeout(120_000)
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || 'Git could not complete the repository update.');
  return { stdout: result.stdout || '' };
}

async function getPublicRepositories(forceRefresh = false) {
  if (!forceRefresh && repoCache.repositories && Date.now() < repoCache.until) return repoCache.repositories;

  const repositories = [];
  for (let page = 1; page <= 10; page += 1) {
    const url = `https://api.github.com/users/${owner}/repos?type=owner&sort=created&direction=desc&per_page=100&page=${page}`;
    const response = await fetch(url, {
      headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'Pongki-Portfolio-Project-Manager' },
      signal: AbortSignal.timeout(15_000)
    });
    if (!response.ok) throw new Error(`GitHub could not return your repositories (${response.status}).`);
    const batch = await response.json();
    if (!Array.isArray(batch)) throw new Error('GitHub returned an unexpected repository list.');

    repositories.push(...batch.filter((repo) =>
      repo.owner?.login?.toLowerCase() === owner.toLowerCase() &&
      !repo.private && !repo.fork && repo.name.toLowerCase() !== 'pongki-portfolio'
    ));
    if (batch.length < 100) break;
  }

  repoCache = { until: Date.now() + 60_000, repositories };
  return repositories;
}

function projectFile(repositories, requestedStatuses, previousConfig) {
  const previousByName = new Map((previousConfig.projects || []).map((project) => [project.name.toLowerCase(), project]));
  const requestedByName = new Map();
  for (const requested of requestedStatuses) {
    if (!requested || typeof requested.name !== 'string' || typeof requested.status !== 'string') {
      throw new Error('One of the project settings is incomplete.');
    }
    const name = requested.name.trim();
    if (!/^[a-zA-Z0-9._-]{1,100}$/.test(name) || !allowedStatuses.has(requested.status)) {
      throw new Error(`Invalid project setting for ${name || 'an unnamed repository'}.`);
    }
    if (requestedByName.has(name.toLowerCase())) throw new Error(`The repository ${name} appears more than once.`);
    const liveUrl = typeof requested.liveUrl === 'string' ? requested.liveUrl.trim() : '';
    if (liveUrl) {
      let parsed;
      try { parsed = new URL(liveUrl); } catch { throw new Error(`The live URL for ${name} is not valid.`); }
      if (parsed.protocol !== 'https:') throw new Error(`The live URL for ${name} must start with https://.`);
    }
    const data = requested.data && typeof requested.data === 'object' ? requested.data : {};
    requestedByName.set(name.toLowerCase(), { status: requested.status, liveUrl, data });
  }

  const projects = repositories.map((repo) => {
    const key = repo.name.toLowerCase();
    const previous = previousByName.get(key) || {};
    const requested = requestedByName.get(key);
    const data = requested?.data || {};
    const languages = Array.isArray(data.languages) ? [...new Set(data.languages.filter((item) => typeof item === 'string').map((item) => item.trim()).filter(Boolean))].slice(0, 30) : previous.languages || (repo.language ? [repo.language] : []);
    return {
      name: repo.name,
      title: (typeof data.title === 'string' ? data.title : previous.title || repo.name).slice(0, 120),
      description: (typeof data.description === 'string' ? data.description : repo.description || previous.description || '').slice(0, 1200),
      url: repo.html_url,
      liveUrl: requested?.liveUrl ?? previous.liveUrl ?? repo.homepage ?? '',
      language: repo.language || previous.language || '',
      languages,
      stars: Number.isInteger(repo.stargazers_count) ? repo.stargazers_count : 0,
      status: requested?.status || previous.status || 'github',
      icon: typeof data.icon === 'string' ? data.icon.slice(0, 300) : previous.icon || '',
      category: (typeof data.category === 'string' ? data.category : previous.category || '').slice(0, 120),
      meta: Array.isArray(data.meta) ? data.meta.filter((row) => row && typeof row.label === 'string' && typeof row.value === 'string').slice(0, 8).map((row) => ({ label: row.label.slice(0, 60), value: row.value.slice(0, 400) })) : previous.meta || [],
      storyEnabled: data.storyEnabled === undefined ? previous.storyEnabled ?? true : Boolean(data.storyEnabled),
      storyTitle: (typeof data.storyTitle === 'string' ? data.storyTitle : previous.storyTitle || 'Project overview').slice(0, 100),
      story: (typeof data.story === 'string' ? data.story : previous.story || '').slice(0, 3000),
      workflowEnabled: data.workflowEnabled === undefined ? previous.workflowEnabled ?? false : Boolean(data.workflowEnabled),
      workflowTitle: (typeof data.workflowTitle === 'string' ? data.workflowTitle : previous.workflowTitle || 'Project workflow').slice(0, 100),
      workflowSteps: Array.isArray(data.workflowSteps) ? data.workflowSteps.filter((step) => typeof step === 'string').map((step) => step.slice(0, 100)).slice(0, 12) : previous.workflowSteps || [],
      statusFlowEnabled: data.statusFlowEnabled === undefined ? previous.statusFlowEnabled ?? false : Boolean(data.statusFlowEnabled),
      statusFlowTitle: (typeof data.statusFlowTitle === 'string' ? data.statusFlowTitle : previous.statusFlowTitle || 'Project status').slice(0, 100),
      statusSteps: Array.isArray(data.statusSteps) ? data.statusSteps.filter((step) => typeof step === 'string').map((step) => step.slice(0, 100)).slice(0, 12) : previous.statusSteps || [],
      noteEnabled: data.noteEnabled === undefined ? previous.noteEnabled ?? false : Boolean(data.noteEnabled),
      noteTitle: (typeof data.noteTitle === 'string' ? data.noteTitle : previous.noteTitle || '').slice(0, 100),
      note: (typeof data.note === 'string' ? data.note : previous.note || '').slice(0, 1000),
      galleryEnabled: data.galleryEnabled === undefined ? previous.galleryEnabled ?? false : Boolean(data.galleryEnabled),
      galleryTitle: (typeof data.galleryTitle === 'string' ? data.galleryTitle : previous.galleryTitle || '').slice(0, 120),
      gallery: Array.isArray(data.gallery) ? data.gallery.filter((item) => item && typeof item.src === 'string').slice(0, 20).map((item) => ({ src: item.src.slice(0, 500), alt: String(item.alt || '').slice(0, 300), caption: String(item.caption || '').slice(0, 120) })) : previous.gallery || [],
      livePreviewEnabled: data.livePreviewEnabled === undefined ? previous.livePreviewEnabled ?? false : Boolean(data.livePreviewEnabled)
    };
  });

  return { owner, projects };
}

async function publishProjectSettings(request, response) {
  if (!isLocalRequest(request)) return sendJson(response, 403, { error: 'This manager only accepts requests from its local page.' });
  if (saving) return sendJson(response, 409, { error: 'A save is already running. Wait for it to finish.' });

  saving = true;
  try {
    const body = await readRequestBody(request);
    if (!Array.isArray(body.statuses)) throw new Error('The submitted project settings are missing.');

    const { stdout: branch } = await git(['branch', '--show-current']);
    if (branch.trim() !== 'main') throw new Error('Switch the portfolio checkout to the main branch, then reopen this manager.');

    const { stdout: stagedFiles } = await git(['diff', '--cached', '--name-only']);
    const stagedList = stagedFiles.split(/\r?\n/).filter(Boolean);
    const projectFileOnly = (file) => file === 'portfolio-projects.json' || file.startsWith('assets/project-icons/');
    if (stagedList.some((file) => !projectFileOnly(file))) {
      throw new Error('Other files are staged in this checkout. Commit or unstage those files before publishing project settings.');
    }

    const repositories = await getPublicRepositories(true);
    const settings = projectFile(repositories, body.statuses, JSON.parse(await readFile(configPath, 'utf8')));
    const nextContent = `${JSON.stringify(settings, null, 2)}\n`;
    const previousContent = await readFile(configPath, 'utf8').catch(() => '');
    const changed = previousContent !== nextContent;
    const { stdout: configChanges } = await git(['diff', '--name-only', '--', 'portfolio-projects.json']);
    const hasPendingConfig = configChanges.split(/\r?\n/).includes('portfolio-projects.json');
    const hasPendingProjectChanges = stagedList.length > 0 || hasPendingConfig;

    if (changed || hasPendingProjectChanges) {
      await writeFile(configPath, nextContent, 'utf8');
      const iconFiles = await readdir(iconDirectory).catch(() => []);
      await git(['add', '--', 'portfolio-projects.json', ...(iconFiles.length ? ['assets/project-icons'] : [])]);
      const { stdout: newlyStagedFiles } = await git(['diff', '--cached', '--name-only']);
      if (newlyStagedFiles.split(/\r?\n/).filter(Boolean).some((file) => file !== 'portfolio-projects.json' && !file.startsWith('assets/project-icons/'))) {
        throw new Error('The manager found another staged file and stopped before committing.');
      }
      await git(['commit', '-m', 'Update portfolio project details']);
    }

    const { stdout: pushOutput } = await git(['push', 'origin', 'main']);
    sendJson(response, 200, {
      message: changed ? 'Project details saved and pushed to GitHub.' : 'No project changes were needed. GitHub is up to date.',
      details: pushOutput.trim()
    });
  } catch (error) {
    sendJson(response, 400, { error: error.message || 'The project settings could not be published.' });
  } finally {
    saving = false;
  }
}

const server = createServer(async (request, response) => {
  const requestUrl = new URL(request.url || '/', `http://${host}:${port}`);
  if (request.headers.host !== `${host}:${port}`) return sendJson(response, 403, { error: 'Use the local manager address.' });

  if (request.method === 'GET' && requestUrl.pathname === '/') {
    try {
      response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
      response.end(await readFile(pagePath));
    } catch {
      sendJson(response, 500, { error: 'The project manager page could not be opened.' });
    }
    return;
  }

  if (request.method === 'GET' && requestUrl.pathname === '/manager.js') {
    try {
      response.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
      response.end(await readFile(scriptPath));
    } catch { sendJson(response, 500, { error: 'The manager controls could not be loaded.' }); }
    return;
  }

  if (request.method === 'GET' && requestUrl.pathname === '/api/version') {
    sendJson(response, 200, { backend: 'node-git-worker-retry' });
    return;
  }

  if (request.method === 'GET' && requestUrl.pathname.startsWith('/preview-assets/')) {
    try {
      const relative = decodeURIComponent(requestUrl.pathname.slice('/preview-assets/'.length));
      const assetRoot = path.resolve(projectDirectory, 'assets');
      const assetPath = path.resolve(assetRoot, relative);
      if (!assetPath.startsWith(`${assetRoot}${path.sep}`)) throw new Error('Invalid image path.');
      const extension = path.extname(assetPath).toLowerCase();
      const types = { '.png':'image/png', '.jpg':'image/jpeg', '.jpeg':'image/jpeg', '.webp':'image/webp', '.gif':'image/gif' };
      if (!types[extension]) throw new Error('Unsupported project image.');
      const bytes = await readFile(assetPath);
      response.writeHead(200, { 'Content-Type': types[extension], 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff' });
      response.end(bytes);
    } catch { sendJson(response, 404, { error:'Project image not found.' }); }
    return;
  }

  if (request.method === 'GET' && requestUrl.pathname === '/api/projects') {
    try { sendJson(response, 200, JSON.parse(await readFile(configPath, 'utf8'))); }
    catch { sendJson(response, 500, { error: 'The saved portfolio projects could not be read.' }); }
    return;
  }

  if (request.method === 'GET' && requestUrl.pathname === '/api/repos') {
    try {
      const repositories = await getPublicRepositories(requestUrl.searchParams.get('refresh') === '1');
      sendJson(response, 200, { repositories });
    } catch (error) {
      sendJson(response, 502, { error: error.message || 'GitHub could not return your repositories.' });
    }
    return;
  }

  if (request.method === 'POST' && requestUrl.pathname === '/api/publish') {
    await publishProjectSettings(request, response);
    return;
  }

  if (request.method === 'POST' && requestUrl.pathname === '/api/icon') {
    if (!isLocalRequest(request)) return sendJson(response, 403, { error: 'This manager only accepts requests from its local page.' });
    try {
      const body = await readRequestBody(request);
      const name = typeof body.name === 'string' ? body.name : '';
      if (!/^[a-zA-Z0-9._-]{1,100}$/.test(name) || !['png', 'jpg', 'jpeg', 'webp', 'gif'].includes(body.extension)) throw new Error('Choose a PNG, JPG, WebP, or GIF icon file.');
      const raw = String(body.data || '').replace(/^data:image\/[a-zA-Z0-9.+-]+;base64,/, '');
      const buffer = Buffer.from(raw, 'base64');
      if (!buffer.length || buffer.length > 3_000_000) throw new Error('The icon must be smaller than 3 MB.');
      await mkdir(iconDirectory, { recursive: true });
      const filename = `${name.toLowerCase()}.${body.extension === 'jpeg' ? 'jpg' : body.extension}`;
      await writeFile(path.join(iconDirectory, filename), buffer);
      sendJson(response, 200, { path: `assets/project-icons/${filename}` });
    } catch (error) { sendJson(response, 400, { error: error.message || 'The icon could not be saved.' }); }
    return;
  }

  if (request.method === 'POST' && requestUrl.pathname === '/api/shutdown') {
    if (!isLocalRequest(request)) return sendJson(response, 403, { error: 'This manager only accepts requests from its local page.' });
    sendJson(response, 200, { message: 'The project manager is closing.' });
    setTimeout(() => server.close(() => process.exit(0)), 50);
    return;
  }

  sendJson(response, 404, { error: 'This manager page was not found.' });
});

server.listen(port, host, () => {
  console.log(`Portfolio project manager listening on http://${host}:${port}`);
});

server.on('error', (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
