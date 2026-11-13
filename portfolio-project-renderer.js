(() => {
  const icons = {C:'c-plain','C#':'csharp-plain','C++':'cplusplus-plain',CSS:'css3-plain',Dart:'dart-plain',Go:'go-plain',HTML:'html5-plain',Java:'java-plain',JavaScript:'javascript-plain',Kotlin:'kotlin-plain',PHP:'php-plain',Python:'python-plain',Ruby:'ruby-plain',Rust:'rust-original',Swift:'swift-plain',TypeScript:'typescript-plain'};
  const safe = (url, host) => { try { const u=new URL(url,location.href); return (!host||u.hostname===host)&&['https:','http:'].includes(u.protocol)?u:null; } catch { return null; } };
  const iconSource = (project) => {
    const path=String(project.icon||'').trim();
    if(!path)return null;
    if(/^https?:\/\//i.test(path)){
      const linked=safe(path);
      if(!linked)return null;
      const match=linked.hostname==='github.com'&&linked.pathname.match(/^\/([^/]+)\/([^/]+)\/(?:blob|raw)\/([^/]+)\/(.+)$/);
      if(match)return `https://raw.githubusercontent.com/${encodeURIComponent(match[1])}/${encodeURIComponent(match[2])}/${encodeURIComponent(match[3])}/${match[4].split('/').map(encodeURIComponent).join('/')}`;
      return linked.href;
    }
    const relative=path.replace(/\\/g,'/').replace(/^\/+/,''),parts=relative.split('/').filter(Boolean);
    if(!parts.length||parts.some(part=>part==='.'||part==='..'))return null;
    if(relative.startsWith('assets/project-icons/'))return safe(relative)?.href||null;
    const repo=safe(project.url,'github.com');
    const [owner,name]=repo?.pathname.split('/').filter(Boolean)||[];
    if(!owner||!name)return null;
    const branch=encodeURIComponent(project.defaultBranch||'main');
    const filePath=parts.map(encodeURIComponent).join('/');
    return `https://raw.githubusercontent.com/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/${branch}/${filePath}`;
  };
  function render(projects) {
    const groups={live:document.querySelector('.live-projects .project-grid'),'in-progress':document.querySelector('.in-progress-projects .project-grid'),github:document.getElementById('github-project-grid')};
    Object.values(groups).forEach(grid=>grid?.replaceChildren());
    const make=(p)=>{
      const card=document.createElement('article');card.className='project';if(p.status==='live'||p.status==='in-progress')card.classList.add('project-portfolio-wide');const body=document.createElement('div');
      const top=document.createElement('div');top.className='project-top';const row=document.createElement('div');row.className='project-link';
      let icon;const iconUrl=iconSource(p);if(iconUrl){icon=document.createElement('img');icon.src=iconUrl;icon.alt=`${p.title||p.name} icon`;icon.loading='lazy';icon.addEventListener('error',()=>{const fallback=document.createElement('span');fallback.className='project-icon github-project-icon';fallback.setAttribute('aria-hidden','true');fallback.textContent=(p.name||'GH').slice(0,2).toUpperCase();icon.replaceWith(fallback)},{once:true})}else{icon=document.createElement('span');icon.setAttribute('aria-hidden','true');icon.textContent=(p.name||'GH').slice(0,2).toUpperCase()}icon.className='project-icon github-project-icon';row.append(icon);
      const badge=document.createElement('span');badge.className=`tag project-status-badge project-status-${p.status}`;badge.textContent=p.status==='live'?'Live':p.status==='in-progress'?'In progress':'GitHub project';row.append(badge);top.append(row);body.append(top);
      const h=document.createElement('h3');h.textContent=p.title||p.name;body.append(h);
      if(p.description){const d=document.createElement('p');d.textContent=p.description;body.append(d)}
      if(p.meta?.length){const meta=document.createElement('div');meta.className='project-meta';p.meta.forEach(x=>{if(!x.label||!x.value)return;const line=document.createElement('span'),b=document.createElement('b');b.textContent=x.label;line.append(b,document.createTextNode(` ${x.value}`));meta.append(line)});body.append(meta)}
      const story=document.createElement('div');story.className='project-story';let hasStory=false;
      if(p.storyEnabled){const label=document.createElement('span');label.className='project-story-label';label.textContent=p.storyTitle||'Project overview';story.append(label);String(p.story||'').split(/\n+/).filter(Boolean).forEach(t=>{const para=document.createElement('p');para.textContent=t;story.append(para)});hasStory=true}
      const addFlow=(enabled,title,steps)=>{if(!enabled||!steps?.length)return;const box=document.createElement('div');box.className='project-status';const label=document.createElement('span');label.className='project-story-label';label.textContent=title;const flow=document.createElement('div');flow.className='workflow-steps';steps.forEach((t,i)=>{if(i){const arrow=document.createElement('i');arrow.textContent='→';arrow.setAttribute('aria-hidden','true');flow.append(arrow)}const chip=document.createElement('span');chip.textContent=t;flow.append(chip)});box.append(label,flow);story.append(box);hasStory=true};
      addFlow(p.workflowEnabled,p.workflowTitle,p.workflowSteps);addFlow(p.statusFlowEnabled,p.statusFlowTitle,p.statusSteps);
      if(p.noteEnabled&&p.note){const box=document.createElement('div');box.className='project-agent-note';const b=document.createElement('strong');b.textContent=p.noteTitle||'Project note';const t=document.createElement('p');t.textContent=p.note;box.append(b,t);story.append(box);hasStory=true}if(hasStory)body.append(story);
      if(p.languages?.length){const langs=document.createElement('div');langs.className='project-languages';const label=document.createElement('span');label.className='language-caption';label.textContent='Languages';langs.append(label);p.languages.forEach(name=>{const chip=document.createElement('span');chip.className='project-language';if(icons[name]){const i=document.createElement('i');i.className=`github-language-icon devicon-${icons[name]} colored`;i.setAttribute('aria-hidden','true');chip.append(i)}else{const i=document.createElement('span');i.className='language-fallback-icon';i.textContent='⌘';i.setAttribute('aria-hidden','true');chip.append(i)}chip.append(document.createTextNode(name));langs.append(chip)});body.append(langs)}
      if(p.galleryEnabled&&p.gallery?.length){const details=document.createElement('details');details.className='project-gallery';const summary=document.createElement('summary');summary.textContent=`${p.galleryTitle||'Explore project'} · ${p.gallery.length} ${p.gallery.length===1?'screen':'screens'}`;const grid=document.createElement('div');grid.className='project-gallery-grid';p.gallery.forEach(item=>{const a=document.createElement('a');a.href=item.src;a.target='_blank';a.rel='noopener noreferrer';const img=document.createElement('img');img.src=item.src;img.alt=item.alt||item.caption||'';img.loading='lazy';const caption=document.createElement('span');caption.textContent=item.caption||'View screenshot';a.append(img,caption);grid.append(a)});details.append(summary,grid);body.append(details)}
      const foot=document.createElement('div');foot.className='project-foot';const tag=document.createElement('span');tag.className='tag';tag.textContent=p.category||'Web development';const actions=document.createElement('span');actions.className='project-actions';
      const live=safe(p.liveUrl,'');if(live&&live.protocol==='https:'){const a=document.createElement('a');a.href=live.href;a.target='_blank';a.rel='noopener noreferrer';a.textContent='Open live site ↗';actions.append(a);if(p.livePreviewEnabled){const details=document.createElement('details');details.className='live-project-preview';const summary=document.createElement('summary');summary.textContent=`Explore ${p.title||p.name} live site`;const content=document.createElement('div');content.className='live-project-preview-content';const iframe=document.createElement('iframe');iframe.title=`${p.title||p.name} live website`;iframe.src=live.href;iframe.loading='lazy';iframe.referrerPolicy='strict-origin-when-cross-origin';content.append(iframe);details.append(summary,content);body.append(details)}}
      const source=safe(p.url,'github.com');if(source){const a=document.createElement('a');a.href=source.href;a.target='_blank';a.rel='noopener noreferrer';a.textContent='Source code ↗';actions.append(a)}
      foot.append(tag,actions);card.append(body,foot);return card;
    };
    projects.filter(p=>p&&p.status!=='hidden').forEach(p=>{const key=p.status==='live'?'live':p.status==='in-progress'?'in-progress':'github';groups[key]?.append(make(p))});
    document.querySelectorAll('.project-group').forEach(group=>{group.hidden=!group.querySelector('.project-grid')?.children.length});
    const section=document.getElementById('github-projects'),grid=groups.github,status=document.getElementById('github-projects-status');section.hidden=!grid.children.length;status.textContent=`${grid.children.length} public ${grid.children.length===1?'project':'projects'} are listed here. Their status is managed in your local project app.`;
  }
  window.addEventListener('load',()=>fetch('portfolio-projects.json',{cache:'no-store'}).then(r=>r.json()).then(data=>{if(data.owner==='Pongki69'&&Array.isArray(data.projects))render(data.projects)}).catch(()=>{}),{once:true});
})();
