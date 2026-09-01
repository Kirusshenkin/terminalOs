# -*- coding: utf-8 -*-
HEAD = open("Main.dc.html", encoding="utf-8").read().split("<x-dc>")[0]

CSS_BASE = '''    body { margin: 0; font-family: "IBM Plex Mono", ui-monospace, Menlo, monospace; }
    a { color: #5BE87F; } a:hover { color: #9DF7B4; }
    .glow { text-shadow: 0 0 6px rgba(91,232,127,.45); }
    .scan { background-image: repeating-linear-gradient(to bottom, rgba(0,0,0,.34) 0 1px, transparent 1px 3px); }
    .vig { background: radial-gradient(120% 90% at 50% 45%, transparent 52%, rgba(0,0,0,.72) 100%); }
    .card { border: 1px solid rgba(91,232,127,.22); background: rgba(91,232,127,.035); }
    .card:hover { border-color: rgba(91,232,127,.5); }
    .row:hover { background: rgba(91,232,127,.06); }
    .dim { color: #2E7A45; } .mid { color: #3E9E5A; } .hi { color: #9DF7B4; } .amb { color: #C9A227; }
    .lbl { font-size: 10.5px; letter-spacing: .16em; color: #2E7A45; }
    .hr { height: 1px; background: rgba(91,232,127,.22); }
    .btn { border: 1px solid rgba(91,232,127,.35); color: #5BE87F; padding: 3px 10px; font-size: 11px; letter-spacing: .06em; cursor: pointer; }
    .btn:hover { border-color: #5BE87F; color: #9DF7B4; }
    .btn.pri { background: #5BE87F; color: #071008; border-color: #5BE87F; }
    .btn.warn { border-color: rgba(201,162,39,.5); color: #C9A227; }
'''

def frame(title, tabs_html, body, status_left, css_extra="", script=None, right_status="PROD-01 · V2BOX · TOUCH ID"):
    sc = ('<script data-dc-script>\n' + script + '\n</script>') if script else ''
    return HEAD + '''<x-dc>
<helmet>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&display=swap">
  <style>
''' + CSS_BASE + css_extra + '''
  </style>
</helmet>

<div style="width: 1200px; height: 760px; background: #05080A; padding: 22px; box-sizing: border-box; position: relative;">
  <div style="width: 100%; height: 100%; background: #071008; border-radius: 26px; position: relative; overflow: hidden; box-shadow: inset 0 0 90px rgba(0,0,0,.9), inset 0 0 20px rgba(91,232,127,.06);">
    <div class="glow" style="position: absolute; inset: 0; padding: 26px 32px; box-sizing: border-box; color: #5BE87F; font-size: 12.5px; display: flex; flex-direction: column;">

      <div style="display: flex; align-items: baseline; gap: 22px; padding-bottom: 6px;">
        <span style="letter-spacing: .2em; color: #3E9E5A;">HELM</span>
        ''' + tabs_html + '''
        <div style="flex-grow: 1;"></div>
        <span class="dim" style="letter-spacing: .12em;">''' + right_status + '''</span>
      </div>
      <div class="hr" style="margin-bottom: 14px;"></div>

      <div style="flex-grow: 1; min-height: 0; display: flex; gap: 22px;">
''' + body + '''
      </div>

      <div class="hr" style="margin: 12px 0 8px;"></div>
      <div style="display: flex; gap: 24px; color: #2E7A45; letter-spacing: .1em; font-size: 11px;">
        ''' + status_left + '''
        <div style="flex-grow: 1;"></div><span>КОТЯТА СПЯТ</span>
      </div>
    </div>
    <div class="scan" style="position: absolute; inset: 0; pointer-events: none;"></div>
    <div class="vig" style="position: absolute; inset: 0; pointer-events: none;"></div>
  </div>
</div>

</x-dc>
''' + sc + '''
</body>
</html>
'''

def tabs(active, items):
    out = []
    for name in items:
        if name == active:
            out.append('<span class="hi" style="letter-spacing: .1em;">▸ %s</span>' % name)
        else:
            out.append('<span class="mid" style="letter-spacing: .1em;">&nbsp;&nbsp;%s</span>' % name)
    return "\n        ".join(out)

WIN_TABS = ["ХОСТЫ", "PROD-01", "SFTP · PROD-01", "DOCKER", "МОНИТОРИНГ", "КЛЮЧИ", "ТЕМА", "+"]

def sidenav(active):
    items = ["хосты", "ключи", "проброс портов", "сниппеты", "известные хосты", "журнал"]
    rows = []
    for it in items:
        cls = "hi" if it == active else "mid"
        mark = "▸" if it == active else "&nbsp;"
        rows.append('<div class="%s" style="padding: 3px 0; cursor: pointer;">%s %s</div>' % (cls, mark, it))
    return '''        <div style="width: 168px; flex-shrink: 0; display: flex; flex-direction: column; gap: 2px;">
          <div class="lbl" style="margin-bottom: 8px;">-- РАЗДЕЛ --</div>
          ''' + "\n          ".join(rows) + '''
        </div>'''

# ====================================================================== ХОСТЫ
hosts_body = sidenav("хосты") + '''
        <div style="flex-grow: 1; min-width: 0; border-left: 1px solid rgba(91,232,127,.18); padding-left: 22px; display: flex; flex-direction: column; gap: 16px; overflow: hidden;">
          <div style="display: flex; gap: 10px; align-items: center;">
            <div style="flex-grow: 1; border: 1px solid rgba(91,232,127,.3); padding: 7px 12px; display: flex; gap: 8px; align-items: center;">
              <span class="dim">&gt;</span><span class="mid">найти хост, тег, группу или user@host…</span>
              <span style="display: inline-block; width: 7px; height: 13px; background: #5BE87F; margin-left: 2px;"></span>
            </div>
            <div class="btn pri">ПОДКЛЮЧИТЬСЯ</div>
          </div>
          <div style="display: flex; gap: 10px; align-items: center;">
            <div class="btn">+ НОВЫЙ ХОСТ</div><div class="btn">ИМПОРТ ~/.ssh/config</div>
            <div style="flex-grow: 1;"></div>
            <span class="dim" style="font-size: 11px;">вид:</span><span class="hi" style="font-size: 11px;">▦ сетка</span><span class="dim" style="font-size: 11px;">≡ список</span>
          </div>

          <div class="lbl">ГРУППЫ · {{groupHint}}</div>
          <div style="display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px;">
            <sc-for list="{{groups}}" as="g" hint-placeholder-count="4">
              <div class="card" onClick="{{ g.pick }}" style="padding: 10px 12px; cursor: pointer; border-color: {{g.br}};">
                <div style="display: flex; align-items: baseline; gap: 8px;"><span style="color: {{g.dot}};">■</span><span class="hi">{{g.name}}</span></div>
                <div class="dim" style="font-size: 11px; margin-top: 3px;">{{g.n}} · {{g.env}}</div>
              </div>
            </sc-for>
          </div>

          <div class="lbl">ХОСТЫ · {{hostCount}}</div>
          <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; overflow: hidden;">
            <sc-for list="{{hosts}}" as="h" hint-placeholder-count="9">
              <div class="card" style="padding: 10px 12px; display: flex; gap: 11px; align-items: center; cursor: pointer;">
                <div style="width: 30px; height: 30px; border: 1px solid rgba(91,232,127,.35); display: flex; align-items: center; justify-content: center; font-size: 10px; color: #3E9E5A; flex-shrink: 0;">{{h.os}}</div>
                <div style="min-width: 0;">
                  <div style="display: flex; gap: 6px; align-items: baseline;"><span class="hi" style="white-space: nowrap;">{{h.name}}</span><span style="color: #C9A227; font-size: 11px;">{{h.warn}}</span></div>
                  <div class="dim" style="font-size: 11px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{h.tags}}</div>
                </div>
              </div>
            </sc-for>
          </div>
        </div>'''
hosts_script = '''class Component extends DCLogic {
  renderVals() {
    const sel = this.state.group ?? null;
    const groups = [
      { id: 'prod', name: 'prod', n: '9 хостов', env: 'прод, красная тема', dot: '#E0673F' },
      { id: 'games', name: 'games', n: '4 хоста', env: 'стейдж', dot: '#7AA2E3' },
      { id: 'lab',  name: 'lab',  n: '3 хоста', env: 'дев', dot: '#3E9E5A' },
      { id: 'misc',  name: 'без группы', n: '4 хоста', env: '—', dot: '#2E7A45' },
    ];
    const all = [
      ['app-1','UBU','ssh, prod, stage','prod',''], ['worker-1','UBU','ssh, prod, api','prod',''],
      ['node-2','UBU','ssh, prod, api','prod',''], ['node-3','UBU','ssh, prod, api','prod','!'],
      ['node-4','UBU','ssh, prod, api','prod',''], ['worker-2','UBU','ssh, prod, worker','prod','!'],
      ['lobby','UBU','ssh, lobby, games','games',''], ['web.dev','UBU','ssh, dev, games','games',''],
      ['lab.dev','DEB','ssh, lab','lab',''], ['lab.dev new','DEB','ssh, lab','lab',''],
      ['203.0.113.9','SRV','ssh, telnet, root','misc',''], ['203.0.113.24','SRV','ssh, root','misc',''],
    ];
    const hosts = all.filter(h => !sel || h[3] === sel).map(([name, os, tags, g, warn]) => ({ name, os, tags, warn }));
    return {
      groups: groups.map(g => ({ ...g, br: sel === g.id ? '#5BE87F' : 'rgba(91,232,127,.22)',
                                  pick: () => this.setState({ group: sel === g.id ? null : g.id }) })),
      groupHint: sel ? 'фильтр: ' + sel + ' (нажми ещё раз — снять)' : 'нажми, чтобы отфильтровать',
      hosts, hostCount: hosts.length + ' из ' + all.length,
    };
  }
}'''
open("Hosts.dc.html","w",encoding="utf-8").write(frame("Хосты", tabs("ХОСТЫ", WIN_TABS), hosts_body,
    "<span>20 ХОСТОВ · 4 ГРУППЫ</span><span>3 ПОДКЛЮЧЕНО</span>", script=hosts_script, right_status="V2BOX · TOUCH ID"))

# ====================================================================== SFTP
def filelist(title, crumbs, rows, selected=None):
    r = []
    for i, (name, perm, date, size, kind) in enumerate(rows):
        bg = "background: rgba(91,232,127,.09);" if i == selected else ""
        r.append('''            <div class="row" style="display: grid; grid-template-columns: 1fr 150px 70px 70px; gap: 8px; padding: 5px 8px; cursor: pointer; %s">
              <div><div class="%s">%s</div><div class="dim" style="font-size: 10.5px;">%s</div></div>
              <div class="mid" style="font-size: 11.5px;">%s</div><div class="mid" style="font-size: 11.5px;">%s</div><div class="dim" style="font-size: 11.5px;">%s</div>
            </div>''' % (bg, "hi" if kind == "папка" else "", name, perm, date, size, kind))
    return '''        <div style="flex: 1 1 0; min-width: 0; display: flex; flex-direction: column; gap: 8px;">
          <div style="display: flex; align-items: center; gap: 10px;"><span class="lbl">%s</span><div style="flex-grow: 1;"></div><span class="dim" style="font-size: 11px;">фильтр</span><span class="dim" style="font-size: 11px;">действия ▾</span></div>
          <div style="display: flex; gap: 8px; align-items: center; font-size: 12px;"><span class="dim">‹ ›</span><span class="mid">%s</span></div>
          <div class="lbl" style="display: grid; grid-template-columns: 1fr 150px 70px 70px; gap: 8px; padding: 0 8px 6px; border-bottom: 1px solid rgba(91,232,127,.18);"><span>ИМЯ</span><span>ИЗМЕНЁН</span><span>РАЗМЕР</span><span>ТИП</span></div>
          <div style="overflow: hidden; display: flex; flex-direction: column;">
%s
          </div>
        </div>''' % (title, crumbs, "\n".join(r))

local_rows = [("..","","","",""),("Documents","drwx------@","27.02.2026 17:01","—","папка"),("Downloads","drwx------@","28.08.2026 16:19","—","папка"),
              ("project","drwxr-xr-x","02.09.2026 01:12","—","папка"),("deploy.tar.gz","-rw-r--r--","01.09.2026 23:40","48,2 МБ","архив"),
              ("docker-compose.yml","-rw-r--r--","01.09.2026 22:18","2,1 КБ","yaml"),(".env.prod","-rw-------","30.08.2026 11:02","640 Б","env")]
remote_rows = [("..","","","",""),("app","drwxr-xr-x root","02.09.2026 01:40","—","папка"),("backups","drwx------ root","01.09.2026 03:00","—","папка"),
               ("docker-compose.yml","-rw-r--r-- root","01.09.2026 22:20","2,1 КБ","yaml"),("nginx.conf","-rw-r--r-- root","28.08.2026 14:11","1,4 КБ","conf"),
               ("deploy.tar.gz","-rw-r--r-- root","загружается…","31,7 / 48,2 МБ","архив")]
sftp_body = '''        <div style="flex-grow: 1; min-width: 0; display: flex; flex-direction: column; gap: 10px;">
          <div style="flex-grow: 1; min-height: 0; display: flex; gap: 22px;">
''' + filelist("ЛОКАЛЬНО", "~ › project › terminal", local_rows, selected=4) + '''
        <div style="width: 1px; background: rgba(91,232,127,.18);"></div>
''' + filelist("PROD-01 · ТО ЖЕ SSH-СОЕДИНЕНИЕ", "/ › srv › app", remote_rows, selected=5) + '''
          </div>
          <div style="border-top: 1px solid rgba(91,232,127,.18); padding-top: 8px; display: flex; flex-direction: column; gap: 5px; font-size: 11.5px;">
            <div style="display: flex; gap: 10px; align-items: center;"><span class="lbl">ОЧЕРЕДЬ</span><span class="mid">deploy.tar.gz → prod-01:/srv/app</span><div style="flex-grow: 1;"></div><span class="hi">66 % · 4,1 МБ/с · 4 с</span></div>
            <div style="height: 3px; background: rgba(91,232,127,.14);"><div style="height: 3px; width: 66%; background: #5BE87F;"></div></div>
            <div class="dim">перетащи файл между панелями или из Finder — это и есть загрузка. Обрыв — докачка с места остановки.</div>
          </div>
        </div>'''
open("SFTP.dc.html","w",encoding="utf-8").write(frame("SFTP", tabs("SFTP · PROD-01", WIN_TABS), sftp_body, "<span>SFTP · PROD-01</span><span>ЧЕРЕЗ V2BOX</span>"))

# ====================================================================== DOCKER + ИНСПЕКТОР
docker_body = '''        <div style="width: 250px; flex-shrink: 0; display: flex; flex-direction: column; gap: 3px;">
          <div class="lbl" style="margin-bottom: 6px;">КОНТЕЙНЕРЫ · PROD-01 · 6</div>
          <sc-for list="{{list}}" as="c" hint-placeholder-count="6">
            <div class="row" onClick="{{ c.pick }}" style="display: flex; gap: 8px; align-items: center; padding: 4px 6px; cursor: pointer; background: {{c.bg}};">
              <span style="color: {{c.dot}};">{{c.mark}}</span><span style="color: {{c.fg}}; flex-grow: 1;">{{c.name}}</span><span class="dim" style="font-size: 11px;">{{c.cpu}}</span>
            </div>
          </sc-for>
          <div style="flex-grow: 1;"></div>
          <div class="dim" style="font-size: 11px;">стек: prod · compose v2</div>
        </div>

        <div style="flex-grow: 1; min-width: 0; border-left: 1px solid rgba(91,232,127,.18); padding-left: 22px; display: flex; flex-direction: column; gap: 12px;">
          <div style="display: flex; align-items: baseline; gap: 14px;">
            <span class="hi" style="font-size: 15px;">{{sel.name}}</span><span class="mid">{{sel.img}}</span><span class="amb">{{sel.state}}</span>
            <div style="flex-grow: 1;"></div>
            <div class="btn">RESTART</div><div class="btn">STOP</div><div class="btn warn">KILL</div><div class="btn warn">RM</div><div class="btn pri">EXEC ▸</div>
          </div>
          <div style="display: flex; gap: 18px;">
            <sc-for list="{{tabs}}" as="t" hint-placeholder-count="5">
              <span onClick="{{ t.pick }}" style="cursor: pointer; color: {{t.fg}}; border-bottom: 1px solid {{t.bar}}; padding-bottom: 3px; letter-spacing: .08em; font-size: 11.5px;">{{t.name}}</span>
            </sc-for>
          </div>

          <sc-if value="{{isLogs}}" hint-placeholder-val="{{ true }}">
            <div style="display: flex; gap: 10px; align-items: center; font-size: 11px;"><span class="hi">● follow</span><span class="dim">--tail 500 --timestamps</span><span class="dim">фильтр: WARN|ERROR</span><div style="flex-grow: 1;"></div><span class="dim">буфер 50 000 строк</span></div>
            <div style="flex-grow: 1; overflow: hidden; line-height: 1.7; font-size: 12px;">
              <sc-for list="{{logs}}" as="l" hint-placeholder-count="12"><div style="color: {{l.fg}}; white-space: pre;">{{l.t}}</div></sc-for>
            </div>
          </sc-if>
          <sc-if value="{{isOverview}}" hint-placeholder-val="{{ false }}">
            <div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 12px;">
              <sc-for list="{{kv}}" as="k" hint-placeholder-count="9"><div class="card" style="padding: 10px 12px;"><div class="lbl">{{k.k}}</div><div class="hi" style="margin-top: 5px; word-break: break-all;">{{k.v}}</div></div></sc-for>
            </div>
          </sc-if>
          <sc-if value="{{isStats}}" hint-placeholder-val="{{ false }}">
            <div style="display: flex; flex-direction: column; gap: 10px; line-height: 1.9;">
              <sc-for list="{{stats}}" as="s" hint-placeholder-count="5"><div style="white-space: pre; color: {{s.fg}};">{{s.t}}</div></sc-for>
              <div class="dim" style="font-size: 11px;">health: {{sel.health}} · restarts: 0 · docker stats --no-stream каждые 3 с</div>
            </div>
          </sc-if>
          <sc-if value="{{isEnv}}" hint-placeholder-val="{{ false }}">
            <div style="line-height: 1.9;"><sc-for list="{{env}}" as="e" hint-placeholder-count="6"><div style="white-space: pre;"><span class="mid">{{e.k}}</span><span class="dim">=</span><span>{{e.v}}</span></div></sc-for>
            <div class="dim" style="font-size: 11px; margin-top: 8px;">секреты замаскированы: значения с PASS, KEY, TOKEN, SECRET в имени не показываются и не копируются в аудит</div></div>
          </sc-if>
          <sc-if value="{{isMounts}}" hint-placeholder-val="{{ false }}">
            <div style="line-height: 1.9;"><sc-for list="{{mounts}}" as="m" hint-placeholder-count="3"><div style="white-space: pre;"><span class="hi">{{m.src}}</span><span class="dim"> → </span><span>{{m.dst}}</span><span class="dim">  {{m.mode}}</span></div></sc-for></div>
          </sc-if>
        </div>'''
docker_script = '''class Component extends DCLogic {
  renderVals() {
    const tab = this.state.tab ?? 'logs';
    const selId = this.state.sel ?? 'worker-billing';
    const cs = [
      { name:'api-gateway', img:'api:2.14', cpu:'12%', state:'running · 6d', ok:1, health:'healthy' },
      { name:'postgres-main', img:'pg:16', cpu:'4%', state:'running · 41d', ok:1, health:'healthy' },
      { name:'redis-cache', img:'redis:7', cpu:'1%', state:'running · 41d', ok:1, health:'—' },
      { name:'worker-billing', img:'wrk:2.1', cpu:'31%', state:'running · 2h · unhealthy', ok:1, health:'unhealthy (3/3 failed)' },
      { name:'nginx-edge', img:'nginx:1.27', cpu:'2%', state:'running · 6d', ok:1, health:'healthy' },
      { name:'migrator', img:'api:2.14', cpu:'0%', state:'exited (0) · 6d', ok:0, health:'—' },
    ];
    const sel = cs.find(c => c.name === selId) || cs[3];
    const tabs = [['overview','ОБЗОР'],['logs','ЛОГИ'],['stats','STATS'],['env','ENV'],['mounts','MOUNTS']];
    return {
      sel,
      list: cs.map(c => ({ ...c, mark: c.ok ? '●' : '○', dot: c.ok ? '#5BE87F' : '#C9A227',
        fg: c.name === sel.name ? '#9DF7B4' : '#5BE87F', bg: c.name === sel.name ? 'rgba(91,232,127,.09)' : 'transparent',
        pick: () => this.setState({ sel: c.name }) })),
      tabs: tabs.map(([id, name]) => ({ id, name, fg: tab === id ? '#9DF7B4' : '#3E9E5A', bar: tab === id ? '#5BE87F' : 'transparent', pick: () => this.setState({ tab: id }) })),
      isLogs: tab === 'logs', isOverview: tab === 'overview', isStats: tab === 'stats', isEnv: tab === 'env', isMounts: tab === 'mounts',
      logs: [
        ['2026-09-02T11:40:58Z  INFO  billing worker started, concurrency=8', '#3E9E5A'],
        ['2026-09-02T11:41:02Z  INFO  job 88f1 charge 1 290 RUB ok 412ms', '#5BE87F'],
        ['2026-09-02T11:41:05Z  INFO  job 88f2 charge 590 RUB ok 388ms', '#5BE87F'],
        ['2026-09-02T11:41:09Z  WARN  upstream billing timeout after 2000ms, retry 1/3', '#C9A227'],
        ['2026-09-02T11:41:12Z  WARN  upstream billing timeout after 2000ms, retry 2/3', '#C9A227'],
        ['2026-09-02T11:41:15Z  ERROR upstream billing unreachable, job 88f3 deferred', '#E0673F'],
        ['2026-09-02T11:41:15Z  INFO  healthcheck: failed (1/3)', '#3E9E5A'],
        ['2026-09-02T11:41:45Z  INFO  healthcheck: failed (2/3)', '#3E9E5A'],
        ['2026-09-02T11:42:15Z  INFO  healthcheck: failed (3/3) → unhealthy', '#C9A227'],
        ['2026-09-02T11:42:20Z  INFO  job 88f4 charge 2 100 RUB ok 401ms', '#5BE87F'],
        ['▮', '#5BE87F'],
      ].map(([t, fg]) => ({ t, fg })),
      kv: [
        { k:'ID', v:'3f9a2c7e11b0' }, { k:'ОБРАЗ', v: sel.img + ' · sha256:9c1e…' }, { k:'СОЗДАН', v:'2 часа назад' },
        { k:'СЕТИ', v:'prod_default 172.19.0.7' }, { k:'ПОРТЫ', v:'127.0.0.1:9100 → 9100' }, { k:'RESTART', v:'unless-stopped' },
        { k:'CMD', v:'node worker.js' }, { k:'COMPOSE', v:'prod / worker' }, { k:'HEALTH', v: sel.health },
      ],
      stats: [
        ['cpu    ████████░░░░░░░░░░░░░░░░░  31 %', '#5BE87F'],
        ['память ████████████░░░░░░░░░░░░░  640 / 1024 МБ', '#5BE87F'],
        ['сеть   ↓ 1,2 МБ/с  ↑ 0,4 МБ/с', '#3E9E5A'],
        ['диск   ↓ 0 Б/с     ↑ 120 КБ/с', '#3E9E5A'],
        ['pids   14', '#3E9E5A'],
      ].map(([t, fg]) => ({ t, fg })),
      env: [['NODE_ENV','production'],['BILLING_URL','https://billing.internal'],['CONCURRENCY','8'],['DATABASE_URL','••••••••'],['REDIS_URL','redis://redis-cache:6379'],['API_KEY','••••••••']].map(([k,v]) => ({k,v})),
      mounts: [{src:'prod_worker_data', dst:'/data', mode:'rw'},{src:'/srv/app/config', dst:'/app/config', mode:'ro'},{src:'/var/run/docker.sock', dst:'/var/run/docker.sock', mode:'ro'}],
    };
  }
}'''
open("DockerInspect.dc.html","w",encoding="utf-8").write(frame("Docker", tabs("DOCKER", WIN_TABS), docker_body, "<span>DOCKER 27.1 · COMPOSE V2</span><span>5 RUNNING · 1 EXITED · 1 UNHEALTHY</span>", script=docker_script))

# ====================================================================== МОНИТОРИНГ
def spark(vals):
    ch = "▁▂▃▄▅▆▇█"
    return "".join(ch[min(7, int(v / 100 * 8))] for v in vals)
import random
random.seed(7)
cores = [62,18,44,9,77,23,31,12]
core_rows = ""
for i, p in enumerate(cores):
    hist = [max(2, min(98, p + random.randint(-18, 18))) for _ in range(28)]
    col = "#C9A227" if p > 70 else "#5BE87F"
    core_rows += '''            <div style="display: flex; gap: 10px; align-items: baseline;"><span class="dim" style="width: 38px;">cpu%d</span><span style="color: %s; letter-spacing: .5px;">%s</span><span style="color: %s; width: 40px; text-align: right;">%d %%</span><span class="dim" style="font-size: 10.5px;">steal %d %%</span></div>
''' % (i, col, spark(hist), col, p, 3 if i in (0, 4) else 0)
mon_body = '''        <div style="flex: 1.15 1 0; min-width: 0; display: flex; flex-direction: column; gap: 14px;">
          <div class="lbl">ЯДРА · 8 · ПОСЛЕДНИЕ 60 С</div>
          <div style="line-height: 1.85; font-size: 12px;">
''' + core_rows + '''          </div>
          <div class="lbl">НАГРУЗКА</div>
          <div style="display: flex; gap: 22px;"><span>load <span class="hi">0.42 0.51 0.48</span></span><span>uptime <span class="hi">41д 6ч</span></span><span>процессы <span class="hi">184</span></span><span class="amb">steal 3 % на cpu0/cpu4 — сосед по гипервизору</span></div>
        </div>
        <div style="width: 1px; background: rgba(91,232,127,.18);"></div>
        <div style="flex: 1 1 0; min-width: 0; display: flex; flex-direction: column; gap: 14px;">
          <div class="lbl">ПАМЯТЬ · MemAvailable</div>
          <div style="line-height: 1.8;">
            <div style="display: flex; justify-content: space-between;"><span>занято <span class="hi">11,4</span> из 32 ГБ</span><span class="dim">swap 0 / 2 ГБ</span></div>
            <div style="height: 8px; background: rgba(91,232,127,.12); display: flex;"><div style="width: 36%; background: #5BE87F;"></div><div style="width: 9%; background: #2E7A45;"></div></div>
            <div class="dim" style="font-size: 11px;">■ приложения 36 % &nbsp; ■ кэш 9 % &nbsp; свободно 55 %</div>
          </div>
          <div class="lbl">ДИСКИ</div>
          <div style="display: flex; flex-direction: column; gap: 8px; font-size: 12px;">
            <div><div style="display: flex; justify-content: space-between;"><span>/ <span class="dim">ext4</span></span><span class="amb">188 / 220 ГБ · 85 %</span></div><div style="height: 5px; background: rgba(91,232,127,.12);"><div style="width: 85%; height: 5px; background: #C9A227;"></div></div></div>
            <div><div style="display: flex; justify-content: space-between;"><span>/var/lib/docker <span class="dim">ext4</span></span><span>61 / 200 ГБ · 30 %</span></div><div style="height: 5px; background: rgba(91,232,127,.12);"><div style="width: 30%; height: 5px; background: #5BE87F;"></div></div></div>
            <div><div style="display: flex; justify-content: space-between;"><span>/backups <span class="dim">nfs</span></span><span>1,1 / 2,0 ТБ · 55 %</span></div><div style="height: 5px; background: rgba(91,232,127,.12);"><div style="width: 55%; height: 5px; background: #5BE87F;"></div></div></div>
          </div>
          <div class="lbl">СЕТЬ · eth0</div>
          <div style="line-height: 1.8; font-size: 12px;">
            <div style="display: flex; gap: 12px; align-items: baseline;"><span class="dim" style="width: 24px;">↓</span><span style="color: #5BE87F; letter-spacing: .5px;">''' + spark([20,25,22,30,45,40,38,52,60,58,55,70,66,62,58,50,44,48,52,49,47,45,42,40,38,41,44,43]) + '''</span><span class="hi">3,1 МБ/с</span></div>
            <div style="display: flex; gap: 12px; align-items: baseline;"><span class="dim" style="width: 24px;">↑</span><span style="color: #3E9E5A; letter-spacing: .5px;">''' + spark([10,12,11,14,18,16,15,20,24,22,21,28,26,25,22,20,18,19,21,20,19,18,17,16,15,16,18,17]) + '''</span><span class="hi">1,1 МБ/с</span></div>
          </div>
          <div class="lbl">КОНТЕЙНЕРЫ</div>
          <div style="font-size: 11.5px; line-height: 1.7;">
            <div style="white-space: pre;"><span class="dim">имя               cpu    память      health</span></div>
            <div style="white-space: pre;">worker-billing    31 %   640 МБ      <span class="amb">unhealthy</span></div>
            <div style="white-space: pre;">api-gateway       12 %   412 МБ      healthy</div>
            <div style="white-space: pre;">postgres-main      4 %   1,2 ГБ      healthy</div>
          </div>
        </div>'''
open("Monitor.dc.html","w",encoding="utf-8").write(frame("Мониторинг", tabs("МОНИТОРИНГ", WIN_TABS), mon_body, "<span>ОДИН КАНАЛ · СНИМОК КАЖДЫЕ 2 С</span><span>БУФЕР 1 Ч</span>"))

# ====================================================================== КЛЮЧИ
keys_body = sidenav("ключи") + '''
        <div style="flex-grow: 1; min-width: 0; border-left: 1px solid rgba(91,232,127,.18); padding-left: 22px; display: flex; flex-direction: column; gap: 14px; overflow: hidden;">
          <div style="display: flex; align-items: baseline; gap: 14px;"><span class="hi" style="font-size: 15px;">authorized_keys</span><span class="mid">root@prod-01</span><span class="dim">/root/.ssh/authorized_keys · 5 ключей</span><div style="flex-grow: 1;"></div><div class="btn pri">+ ДОБАВИТЬ</div><div class="btn">СКОПИРОВАТЬ МОЙ</div></div>
          <div class="lbl" style="display: grid; grid-template-columns: 24px 1.4fr 2fr 1fr 90px; gap: 10px; padding-bottom: 6px; border-bottom: 1px solid rgba(91,232,127,.18);"><span></span><span>КЛЮЧ</span><span>ОТПЕЧАТОК SHA256</span><span>ОПЦИИ</span><span></span></div>
          <div style="display: flex; flex-direction: column; gap: 2px; font-size: 12px;">
            <div class="row" style="display: grid; grid-template-columns: 24px 1.4fr 2fr 1fr 90px; gap: 10px; padding: 7px 0; align-items: center; background: rgba(91,232,127,.06);">
              <span class="hi">●</span><div><div class="hi">ed25519 · you@mac</div><div class="dim" style="font-size: 10.5px;">этим ключом ты подключён сейчас</div></div>
              <span class="mid" style="font-size: 11px; word-break: break-all;">SHA256:q9Xf3…Lm2E</span><span class="dim">—</span><span class="dim" style="font-size: 11px;">твой</span>
            </div>
            <div class="row" style="display: grid; grid-template-columns: 24px 1.4fr 2fr 1fr 90px; gap: 10px; padding: 7px 0; align-items: center;">
              <span>●</span><div><div>ecdsa-p256 · secure-enclave · mbp</div><div class="dim" style="font-size: 10.5px;">Secure Enclave, только с Touch ID</div></div>
              <span class="mid" style="font-size: 11px;">SHA256:Hh0p…9aQz</span><span class="dim">—</span><span class="dim" style="font-size: 11px;">твой</span>
            </div>
            <div class="row" style="display: grid; grid-template-columns: 24px 1.4fr 2fr 1fr 90px; gap: 10px; padding: 7px 0; align-items: center;">
              <span>●</span><div><div>ed25519 · deploy@ci</div><div class="dim" style="font-size: 10.5px;">добавлен 12.06.2026</div></div>
              <span class="mid" style="font-size: 11px;">SHA256:Zt7v…C1kR</span><span class="dim" style="font-size: 11px;">command="deploy.sh", no-pty</span><span class="dim" style="font-size: 11px;">выкл · удалить</span>
            </div>
            <div class="row" style="display: grid; grid-template-columns: 24px 1.4fr 2fr 1fr 90px; gap: 10px; padding: 7px 0; align-items: center;">
              <span class="amb">▲</span><div><div class="amb">rsa-2048 · andrey@old-laptop</div><div class="dim" style="font-size: 10.5px;">RSA короче 3072 бит — слабый. Добавлен 03.2023</div></div>
              <span class="mid" style="font-size: 11px;">SHA256:Bq2m…7xVd</span><span class="dim">—</span><span class="dim" style="font-size: 11px;">выкл · удалить</span>
            </div>
            <div class="row" style="display: grid; grid-template-columns: 24px 1.4fr 2fr 1fr 90px; gap: 10px; padding: 7px 0; align-items: center; opacity: .55;">
              <span class="dim">○</span><div><div class="dim">ed25519 · temp-contractor</div><div class="dim" style="font-size: 10.5px;">отключён (закомментирован) 20.08.2026</div></div>
              <span class="dim" style="font-size: 11px;">SHA256:Nn4a…Ue8L</span><span class="dim">from="10.0.0.0/8"</span><span class="dim" style="font-size: 11px;">вкл · удалить</span>
            </div>
          </div>
          <div class="card" style="padding: 10px 12px; border-color: rgba(201,162,39,.45); font-size: 11.5px;">
            <span class="amb">защита от самоблокировки:</span> удалить ключ, которым ты подключён сейчас, можно только с явным подтверждением. Запись атомарная, копия <span class="mid">authorized_keys.helm.bak</span> остаётся на сервере.
          </div>
          <div class="lbl" style="margin-top: 4px;">ЛОКАЛЬНЫЕ КЛЮЧИ · ~/.ssh</div>
          <div style="display: flex; gap: 10px;">
            <div class="card" style="padding: 8px 12px; flex: 1;"><div class="hi">id_ed25519.pub</div><div class="dim" style="font-size: 11px;">на 6 из 20 хостов</div></div>
            <div class="card" style="padding: 8px 12px; flex: 1;"><div class="hi">secure-enclave (P-256)</div><div class="dim" style="font-size: 11px;">не покидает Мак · на 3 хостах</div></div>
            <div class="card" style="padding: 8px 12px; flex: 1; display: flex; align-items: center; justify-content: center;"><span class="mid">+ сгенерировать новый</span></div>
          </div>
        </div>'''
open("Keys.dc.html","w",encoding="utf-8").write(frame("Ключи", tabs("КЛЮЧИ", WIN_TABS), keys_body, "<span>ОТПЕЧАТКИ СЧИТАЮТСЯ ЛОКАЛЬНО</span><span>ssh-keygen НА СЕРВЕРЕ НЕ НУЖЕН</span>"))

# ====================================================================== ТЕМА
theme_body = '''        <div style="width: 190px; flex-shrink: 0; display: flex; flex-direction: column; gap: 3px;">
          <div class="lbl" style="margin-bottom: 8px;">ТЕМЫ</div>
          <sc-for list="{{themes}}" as="t" hint-placeholder-count="4">
            <div class="row" onClick="{{ t.pick }}" style="display: flex; gap: 8px; align-items: center; padding: 4px 6px; cursor: pointer; background: {{t.bg}};"><span style="color: {{t.swatch}};">■</span><span style="color: {{t.fg}};">{{t.name}}</span></div>
          </sc-for>
          <div class="dim" style="font-size: 11px; margin-top: 12px;">импорт: .itermcolors · alacritty · base16</div>
          <div style="flex-grow: 1;"></div>
          <div class="lbl" style="margin-bottom: 6px;">ПРИВЯЗКА</div>
          <div style="font-size: 11.5px; line-height: 1.7;"><div><span class="dim">по умолчанию</span> Фосфор</div><div><span class="dim">группа prod</span> <span style="color: #E0673F;">Рубин</span></div><div><span class="dim">группа games</span> Лёд</div></div>
        </div>

        <div style="flex-grow: 1; min-width: 0; border-left: 1px solid rgba(91,232,127,.18); padding-left: 22px; display: flex; gap: 22px;">
          <div style="flex: 1 1 0; display: flex; flex-direction: column; gap: 14px;">
            <div class="lbl">ПАЛИТРА ANSI · {{cur.name}}</div>
            <div style="display: grid; grid-template-columns: repeat(8, minmax(0, 1fr)); gap: 5px;">
              <sc-for list="{{cur.ansi}}" as="c" hint-placeholder-count="16"><div style="height: 26px; background: {{c}}; border: 1px solid rgba(255,255,255,.06);"></div></sc-for>
            </div>
            <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; font-size: 11.5px;">
              <div class="card" style="padding: 7px 10px; display: flex; justify-content: space-between;"><span class="dim">текст</span><span style="color: {{cur.fg}};">{{cur.fg}}</span></div>
              <div class="card" style="padding: 7px 10px; display: flex; justify-content: space-between;"><span class="dim">фон</span><span>{{cur.bgc}}</span></div>
              <div class="card" style="padding: 7px 10px; display: flex; justify-content: space-between;"><span class="dim">курсор</span><span style="color: {{cur.cur}};">{{cur.cur}}</span></div>
              <div class="card" style="padding: 7px 10px; display: flex; justify-content: space-between;"><span class="dim">выделение</span><span>{{cur.sel}}</span></div>
            </div>
            <div class="lbl">ШРИФТ</div>
            <div style="display: flex; gap: 8px; font-size: 11.5px;"><div class="card" style="padding: 7px 10px; flex: 1;">IBM Plex Mono · 13</div><div class="card" style="padding: 7px 10px;">лигатуры ●</div><div class="card" style="padding: 7px 10px;">строка 1,4</div></div>
            <div class="lbl">ФОН И СТЕКЛО</div>
            <div style="font-size: 11.5px; display: flex; flex-direction: column; gap: 7px;">
              <div style="display: flex; justify-content: space-between;"><span>картинка</span><span class="mid">нет · выбрать…</span></div>
              <div style="display: flex; gap: 10px; align-items: center;"><span style="width: 110px;">скан-линии</span><div style="flex-grow: 1; height: 3px; background: rgba(91,232,127,.14);"><div style="width: 60%; height: 3px; background: #5BE87F;"></div></div><span class="dim">60 %</span></div>
              <div style="display: flex; gap: 10px; align-items: center;"><span style="width: 110px;">свечение</span><div style="flex-grow: 1; height: 3px; background: rgba(91,232,127,.14);"><div style="width: 45%; height: 3px; background: #5BE87F;"></div></div><span class="dim">45 %</span></div>
              <div style="display: flex; gap: 10px; align-items: center;"><span style="width: 110px;">виньетка</span><div style="flex-grow: 1; height: 3px; background: rgba(91,232,127,.14);"><div style="width: 70%; height: 3px; background: #5BE87F;"></div></div><span class="dim">70 %</span></div>
              <div style="display: flex; gap: 10px; align-items: center;"><span style="width: 110px;">прозрачность окна</span><div style="flex-grow: 1; height: 3px; background: rgba(91,232,127,.14);"><div style="width: 0%; height: 3px; background: #5BE87F;"></div></div><span class="dim">0 %</span></div>
            </div>
          </div>

          <div style="width: 330px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;">
            <div class="lbl">ПРЕДПРОСМОТР</div>
            <div style="flex-grow: 1; background: {{cur.bgc}}; border: 1px solid rgba(255,255,255,.08); padding: 14px; font-size: 12px; line-height: 1.7; color: {{cur.fg}}; text-shadow: 0 0 6px {{cur.glow}};">
              <div><span style="color: {{cur.a2}};">root@prod-01</span>:<span style="color: {{cur.a4}};">~</span># ls -la</div>
              <div><span style="color: {{cur.a4}};">drwxr-xr-x</span>  app  <span style="color: {{cur.a6}};">config</span>  <span style="color: {{cur.a3}};">deploy.sh</span></div>
              <div><span style="color: {{cur.a2}};">root@prod-01</span>:<span style="color: {{cur.a4}};">~</span># docker compose ps</div>
              <div><span style="color: {{cur.a2}};">●</span> api-gateway   <span style="opacity: .7;">Up 6 days</span></div>
              <div><span style="color: {{cur.a3}};">○</span> migrator      <span style="color: {{cur.a3}};">Exited (0)</span></div>
              <div><span style="color: {{cur.a1}};">ERROR</span> upstream billing unreachable</div>
              <div><span style="color: {{cur.a2}};">root@prod-01</span>:<span style="color: {{cur.a4}};">~</span># <span style="display: inline-block; width: 8px; height: 13px; background: {{cur.cur}}; vertical-align: -2px;"></span></div>
            </div>
            <div class="dim" style="font-size: 11px;">меняется живьём — нажми тему слева</div>
          </div>
        </div>'''
theme_script = '''class Component extends DCLogic {
  renderVals() {
    const id = this.state.theme ?? 'phosphor';
    const T = {
      phosphor: { name:'Фосфор', bgc:'#071008', fg:'#5BE87F', cur:'#5BE87F', sel:'#1E5C33', glow:'rgba(91,232,127,.45)', swatch:'#5BE87F',
        ansi:['#0B1A0F','#C4703A','#3E9E5A','#C9A227','#2E7A86','#7C5FA0','#2F8A86','#8DB894','#1E5C33','#E0673F','#5BE87F','#E2C15A','#4FA9C4','#AC84C0','#58ABA3','#9DF7B4'] },
      amber:    { name:'Янтарь', bgc:'#100B03', fg:'#E8A33D', cur:'#F2BC6A', sel:'#4A3410', glow:'rgba(232,163,61,.45)', swatch:'#E8A33D',
        ansi:['#1A1208','#C4433A','#7C8F3B','#E8A33D','#8A6A2E','#A06A7C','#8A8A3E','#D9B98A','#4A3410','#E0673F','#B0C060','#F2BC6A','#C09A5A','#C08AA0','#B0B060','#F4E3C0'] },
      ice:      { name:'Лёд', bgc:'#070B12', fg:'#8FC7E8', cur:'#BFE3FF', sel:'#173048', glow:'rgba(143,199,232,.4)', swatch:'#8FC7E8',
        ansi:['#0C1522','#C45A5A','#5AAE8C','#C4B26A','#4F8FCC','#8C7CC4','#4FB0C4','#A8C4D8','#22354A','#E07A7A','#7AD4AE','#E8D48C','#7AB4EC','#B0A0E8','#7AD0E8','#DCEEFF'] },
      ruby:     { name:'Рубин · прод', bgc:'#12060A', fg:'#E88A9A', cur:'#FFB3C0', sel:'#4A1520', glow:'rgba(232,138,154,.4)', swatch:'#E0673F',
        ansi:['#1E0A10','#E0483F','#7CA05A','#D9A03A','#8A5F9E','#B05A8C','#6E8AA0','#D8A8B0','#4A1520','#FF6B5C','#A0C47A','#F2C15A','#B08ACC','#D080B0','#8AB0C4','#FFD8DE'] },
    };
    const cur = T[id];
    const a = cur.ansi;
    return {
      themes: Object.entries(T).map(([k, v]) => ({ name: v.name, swatch: v.swatch, fg: k === id ? '#9DF7B4' : '#5BE87F', bg: k === id ? 'rgba(91,232,127,.09)' : 'transparent', pick: () => this.setState({ theme: k }) })),
      cur: { ...cur, a1: a[9], a2: a[10], a3: a[11], a4: a[12], a6: a[14] },
    };
  }
}'''
open("Theme.dc.html","w",encoding="utf-8").write(frame("Тема", tabs("ТЕМА", WIN_TABS), theme_body, "<span>ТЕМА — ОТКРЫТЫЙ JSON В themes/</span><span>МОЖНО ДЕРЖАТЬ В GIT</span>", script=theme_script))

# ====================================================================== ВЫПОЛНЕНИЕ РЕЦЕПТА
steps = [("обновить пакеты и unattended-upgrades","✓","готово · 41 с"),
         ("Docker + Compose, лимит логов docker и journald","▸","идёт · 28 с"),("nginx","·","ожидает"),
         ("certbot · app.example.com","·","ожидает · DNS проверен"),("UFW: только 22 80 443 · проверка портов compose","·","ожидает"),
         ("закрыть вход по паролю","·","последним, после проверки ключа")]
step_rows = ""
for name, mark, st in steps:
    col = {"✓":"#3E9E5A","▸":"#9DF7B4","·":"#2E7A45"}[mark]
    step_rows += '            <div style="display: flex; gap: 10px; align-items: baseline; padding: 4px 0;"><span style="color: %s; width: 14px;">%s</span><span style="color: %s; flex-grow: 1;">%s</span><span class="dim" style="font-size: 11px;">%s</span></div>\n' % (col, mark, "#9DF7B4" if mark=="▸" else ("#5BE87F" if mark=="✓" else "#3E9E5A"), name, st)
prov_body = '''        <div style="width: 380px; flex-shrink: 0; display: flex; flex-direction: column; gap: 10px;">
          <div style="display: flex; align-items: baseline; gap: 10px;"><span class="hi" style="font-size: 15px;">рецепт · базовый</span><span class="mid">prod-02 · ubuntu 24.04</span></div>
          <div class="dim" style="font-size: 11.5px;">шаг 2 из 6 · идемпотентно · что уже стоит — пропускается</div>
          <div class="hr"></div>
          <div style="font-size: 12px;">
''' + step_rows + '''          </div>
          <div style="flex-grow: 1;"></div>
          <div style="display: flex; gap: 8px;"><div class="btn warn">ОСТАНОВИТЬ ПОСЛЕ ШАГА</div><div class="btn">ПОКАЗАТЬ КОМАНДЫ</div></div>
          <div class="card" style="padding: 8px 10px; font-size: 11px; border-color: rgba(201,162,39,.4);"><span class="amb">шаг 6</span> закроет вход по паролю только после того, как второе соединение по ключу успешно откроется. Самоблокировка исключена.</div>
        </div>
        <div style="flex-grow: 1; min-width: 0; border-left: 1px solid rgba(91,232,127,.18); padding-left: 22px; display: flex; flex-direction: column; gap: 8px;">
          <div style="display: flex; gap: 10px; align-items: center; font-size: 11px;"><span class="hi">● живой лог</span><span class="dim">шаг 2 · Docker + Compose</span><div style="flex-grow: 1;"></div><span class="dim">sudo не нужен · root</span></div>
          <div style="flex-grow: 1; overflow: hidden; font-size: 11.5px; line-height: 1.65;">
            <div class="dim" style="white-space: pre;">$ install -m 0755 -d /etc/apt/keyrings</div>
            <div class="dim" style="white-space: pre;">$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc</div>
            <div class="dim" style="white-space: pre;">$ echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" &gt; /etc/apt/sources.list.d/docker.list</div>
            <div class="dim" style="white-space: pre;">$ apt-get update -qq</div>
            <div style="white-space: pre;">$ apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin</div>
            <div class="mid" style="white-space: pre;">Reading package lists... Done</div>
            <div class="mid" style="white-space: pre;">The following NEW packages will be installed:</div>
            <div class="mid" style="white-space: pre;">  containerd.io docker-ce docker-ce-cli docker-compose-plugin</div>
            <div class="mid" style="white-space: pre;">Get:1 https://download.docker.com/linux/ubuntu noble/stable amd64 containerd.io amd64 1.7.22-1 [29.5 MB]</div>
            <div class="mid" style="white-space: pre;">Get:2 https://download.docker.com/linux/ubuntu noble/stable amd64 docker-ce-cli amd64 5:27.3.1-1 [15.0 MB]</div>
            <div class="mid" style="white-space: pre;">Fetched 44.5 MB in 3s (14.8 MB/s)</div>
            <div class="mid" style="white-space: pre;">Setting up containerd.io (1.7.22-1) ...</div>
            <div class="mid" style="white-space: pre;">Setting up docker-ce (5:27.3.1-1) ...</div>
            <div style="white-space: pre;">$ cat &gt; /etc/docker/daemon.json  <span class="dim"># log-driver json-file, max-size 10m, max-file 3</span></div>
            <div style="white-space: pre;">$ systemctl enable --now docker</div>
            <div class="hi" style="white-space: pre;">$ docker --version <span style="display: inline-block; width: 8px; height: 13px; background: #5BE87F; vertical-align: -2px;"></span></div>
          </div>
        </div>'''
open("ProvisionRun.dc.html","w",encoding="utf-8").write(frame("Автонастройка", tabs("PROD-02 · НАСТРОЙКА", ["ХОСТЫ","PROD-01","PROD-02 · НАСТРОЙКА","SFTP · PROD-01","+"]), prov_body, "<span>РЕЦЕПТ ЗАПУЩЕН 01:52</span><span>ВЫПОЛНЕНО 1 ИЗ 6</span>", right_status="PROD-02 · V2BOX · ROOT"))
print("7 страниц собрано")
