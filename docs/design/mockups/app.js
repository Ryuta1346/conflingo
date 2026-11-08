'use strict';

// Review-only fixtures. No microphone, network, or persistent storage APIs.
const icons = {
  home:'M3 10 12 3l9 7v10H3Z M9 20v-7h6v7',
  captions:'M4 4h16v13H9l-5 4Z M8 8h8 M8 12h5',
  meeting:'M7 3h10v5H7Z M4 12h6v8H4Z M14 12h6v8h-6Z M12 8v3 M7 11h10',
  folder:'M3 6h7l2 3h9v11H3Z',
  settings:'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8 M12 3v2 M12 19v2 M3 12h2 M19 12h2 M5.6 5.6 7 7 M17 17l1.4 1.4 M5.6 18.4 7 17 M17 7l1.4-1.4',
  mic:'M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0Z M6 10v2a6 6 0 0 0 12 0v-2 M12 18v3 M9 21h6',
  audio:'M3 8h5l5-4v16l-5-4H3Z M17 8a6 6 0 0 1 0 8 M20 5a10 10 0 0 1 0 14',
  sparkle:'m12 3 2.6 6.4L21 12l-6.4 2.6L12 21l-2.6-6.4L3 12l6.4-2.6Z',
  arrow:'M5 12h14 M14 7l5 5-5 5',
  shield:'M12 3 3 7v5c0 5 9 9 9 9s9-4 9-9V7Z M8 12l3 3 5-6',
  cloud:'M6 18a5 5 0 1 1 1-10 6 6 0 0 1 11 1 4.5 4.5 0 1 1 0 9Z',
  check:'m5 12 4 4L19 6',
  stop:'M6 6h12v12H6Z',
  pause:'M8 5v14 M16 5v14',
  play:'m7 4 13 8-13 8Z',
  export:'M12 15V3 M8 7l4-4 4 4 M4 13v7h16v-7',
  expand:'M8 3H3v5 M16 3h5v5 M3 16v5h5 M21 16v5h-5',
  compact:'M3 5h18v14H3Z M12 11h7v6h-7Z',
  warning:'m12 3 10 18H2Z M12 9v5 M12 17v1',
  clock:'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18 M12 7v6l4 2',
  book:'M3 4h7l2 2 2-2h7v15h-7l-2 2-2-2H3Z M12 6v15',
  pin:'m8 3 8 0-1 7 4 4H5l4-4Z M12 14v7',
  close:'m6 6 12 12 M18 6 6 18',
  search:'M10 3a7 7 0 1 0 0 14 7 7 0 0 0 0-14 M15 15l6 6',
  trash:'M3 6h18 M9 6V3h6v3 M6 6l1 15h10l1-15 M10 10v7 M14 10v7',
  document:'M5 3h9l5 5v13H5Z M14 3v6h5 M8 13h8 M8 17h6',
  eye:'M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6'
};
const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${icons[name] || icons.captions}"/></svg>`;
const escapeHTML = value => String(value).replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const button = (label, action, style = '', symbol = '', attrs = '') => `<button class="${style}" data-action="${action}" ${attrs}>${symbol ? icon(symbol) : ''}${label}</button>`;
const nav = (label, screen, style = '', symbol = '') => `<button class="${style}" data-nav="${screen}">${symbol ? icon(symbol) : ''}${label}</button>`;
const pill = (text, type = 'neutral', dot = false) => `<span class="pill ${type}">${dot ? '<span class="dot"></span>' : ''}${text}</span>`;
const fixture = {
  name:'プロダクト定例',
  question:'Can we launch the pilot next Friday, or do we need more time for the security review?',
  answer:'来週金曜は、セキュリティレビューの完了を条件に。',
  reason:'日程を確約する前に、レビューの担当者と完了予定を確認するとよさそうです。',
  quote:'The security review is still in progress. We should have an update by Wednesday.'
};
const state = {
  screen:'meeting', scenario:'normal', theme:'light', scale:1, name:fixture.name,
  consent:false, cloud:false, sharingDocs:false, sourceLang:'日本語', remoteLang:'English',
  conferenceName:'WWDC セッション', source:'English (US)', target:'日本語', only:false, fast:false,
  conferenceRunning:false, meetingActive:false, paused:false, pinned:false, captionSize:18,
  decisions:{decision:'suggested',action:'suggested'}, saved:false, hidden:false,
  profiles:[{name:'プロダクト開発',terms:'ConfLingo, SpeechAnalyzer, pilot=試験導入'},{name:'一般',terms:''}], profile:0,
  sessions:[{id:1,name:'デザインレビュー',type:'Meeting',date:'11月7日',duration:'32分'}, {id:2,name:'WWDC セッション',type:'Conference',date:'11月6日',duration:'48分'}],
  askResult:false, query:'', search:''
};
const labels = {home:'ホーム','conference-setup':'Conference の準備',conference:'Conference',preparation:'Meeting の準備',meeting:'Meeting',floating:'コンパクト表示',review:'振り返り',sessions:'保存したセッション',settings:'設定'};
const scenarios = {
  normal:'通常',empty:'空の状態',permission:'権限確認',preparing:'準備中',paused:'一時停止',stopping:'停止中',denied:'権限拒否',disconnected:'入力切断','stop-failed':'停止失敗',sending:'AI送信中',offline:'オフライン',reconnecting:'再接続中','ai-off':'AIオフ','no-knowledge':'資料なし','no-insights':'提案なし','translation-failed':'翻訳失敗'
};
const availableStates = {
  home:['normal','empty'], 'conference-setup':['normal','permission','preparing','denied'],
  conference:['normal','empty','paused','preparing','stopping','denied','disconnected','stop-failed','translation-failed'],
  preparation:['normal','permission','preparing','denied','no-knowledge'],
  meeting:['normal','empty','paused','stopping','denied','disconnected','stop-failed','sending','offline','reconnecting','ai-off','no-knowledge','no-insights'],
  floating:['normal','paused','stopping','stop-failed','sending','offline','ai-off','no-insights'], review:['normal','empty'],sessions:['normal','empty'],settings:['normal']
};
const app = document.querySelector('#app');
const dialog = document.querySelector('#dialog');
let dialogOrigin;
let toastTimer;

function cloudLabel(){
  if(state.cloud && state.scenario==='sending') return 'AI 送信中';
  if(['offline','reconnecting'].includes(state.scenario)) return state.scenario === 'offline' ? 'AI オフライン' : 'AI 再接続中';
  if(!state.cloud || state.scenario === 'ai-off') return 'クラウドAI オフ';
  return state.paused || state.scenario === 'paused' ? 'AI 送信停止' : 'AI 許可済み・待機';
}
function isInputStopped(){return ['paused','disconnected','denied','empty'].includes(state.scenario) || state.paused;}
function sidebar(){
  const current = state.screen.startsWith('conference') ? 'conference-setup' : ['preparation','meeting','floating','review'].includes(state.screen) ? 'preparation' : state.screen;
  const items = [['home','ホーム','home'],['conference-setup','Conference','captions'],['preparation','Meeting','meeting'],['sessions','保存したセッション','folder']];
  return `<aside class="sidebar"><div class="traffic" aria-hidden="true"><i></i><i></i><i></i></div><div class="brand"><span class="brand-mark">${icon('captions')}</span>ConfLingo</div><div class="nav-label">ワークスペース</div><nav aria-label="メインナビゲーション">${items.map(([screen,label,symbol])=>`<button class="nav-item ${current===screen?'active':''}" data-route="${screen}" ${current===screen?'aria-current="page"':''}>${icon(symbol)}${label}</button>`).join('')}</nav><div class="sidebar-bottom"><button class="nav-item ${current==='settings'?'active':''}" data-route="settings" ${current==='settings'?'aria-current="page"':''}>${icon('settings')}設定</button><div class="local-note">${icon('shield')}Local-first<br>音声認識は、このMacで。</div></div></aside>`;
}
function toolbar(actions=''){
  let section = ['meeting','floating','review','preparation'].includes(state.screen) ? 'Meeting' : state.screen.startsWith('conference') ? 'Conference' : 'ワークスペース';
  const sub = ['meeting','review'].includes(state.screen) ? escapeHTML(state.name) : state.screen==='conference' ? escapeHTML(state.conferenceName) : labels[state.screen];
  return `<header class="toolbar"><div class="breadcrumb"><span>${section}</span><span>/</span><strong>${sub}</strong></div><div class="toolbar-actions">${actions}</div></header>`;
}
function heading(title,subtitle,eyebrow='',right=''){
  return `<div class="page-heading"><div>${eyebrow?`<div class="eyebrow">${eyebrow}</div>`:''}<h1>${title}</h1>${subtitle?`<p class="subtitle">${subtitle}</p>`:''}</div>${right}</div>`;
}
function empty(title,description,symbol='captions',action=''){
  return `<div class="empty">${icon(symbol)}<h2>${title}</h2><p>${description}</p>${action}</div>`;
}
function banner(){
  const items={
    permission:['info','音声へのアクセスを確認します','マイクとMacの音声を使用します。開始操作の後にmacOSの許可画面が開きます。','権限を確認する','grant'],
    preparing:['info','音声認識の準備をしています','選択した言語のモデルを準備しています。準備ができるまで音声は取得しません。','キャンセル','cancel-preparation'],
    paused:['info','音声収集を一時停止しています','新しい音声の取得とAI送信を停止しています。ここまでの発話は保持しています。','再開する','resume'],
    stopping:['info','会議を終了しています','入力を止め、最後の文字起こしを反映しています。終了処理が完了するまでお待ちください。','',''],
    denied:['error','音声へのアクセスが許可されていません','macOSのシステム設定でマイクと画面・システムオーディオの権限を確認してください。','設定手順を見る','permission-help'],
    disconnected:['error','音声入力が切断されました','両方の入力を停止しました。ここまでの発話を保持しています。入力を確認して再開してください。','入力を確認する','input-help'],
    'stop-failed':['error','音声の停止を確認できませんでした','停止が完了するまで、新しい会議の開始・字幕の消去はできません。','停止を再試行','retry-stop'],
    sending:['info','AIが回答を生成しています','必要な確定発話を送信しています。音声収集はこのMacで継続中です。','クラウドAIを停止','cloud-off'],
    offline:['warning','クラウドAIに接続できません','文字起こしはこのMacで続けています。新しいAI提案は接続の回復後に利用できます。','再接続する','reconnect'],
    reconnecting:['info','クラウドAIへの接続を確認中','文字起こしは続いています。AIを停止して会議を続けることもできます。','クラウドAIを停止','cloud-off'],
    'ai-off':['info','クラウドAIはオフです','発話を外部に送信せず、文字起こしを続けています。','送信内容を確認','cloud-consent'],
    'no-knowledge':['warning','参照資料は登録されていません','会話の発話だけを参照します。資料による仕様・日程の裏付けはありません。','',''],
    'translation-failed':['warning','一部の字幕を翻訳できませんでした','原文の文字起こしは継続しています。失敗した訳文は原文とあわせて確認してください。','','']
  };
  const data=items[state.scenario];
  if(!data)return '';
  return `<div class="banner ${data[0]}" role="status">${icon(data[0]==='error'?'warning':'shield')}<div><h3>${data[1]}</h3><p>${data[2]}</p>${data[3]?button(data[3],data[4]):''}</div></div>`;
}
function transport(conference=false){
  const running = conference ? state.conferenceRunning : state.meetingActive;
  const pending = state.scenario==='stopping';
  const failed = state.scenario==='stop-failed';
  const stopped = isInputStopped() || !running;
  const label=pending?'停止処理中':failed?'停止未確認':stopped?'停止中':'取得中';
  const unavailable=['denied','disconnected','preparing','permission'].includes(state.scenario);
  const actions=failed?button('停止を再試行','retry-stop','danger','stop'):pending?button('終了処理中…','noop','','', 'disabled'):conference?
    button(running&&!stopped?'停止する':'開始する',running&&!stopped?'conference-stop':'conference-start',running&&!stopped?'danger':'primary',running&&!stopped?'stop':'play', unavailable?'disabled':''):
    `${button(stopped?'収集を再開':'収集を一時停止',stopped?'resume':'pause','',''+(stopped?'play':'pause'),unavailable?'disabled':'')}${button('会議を終了','end','danger','stop')}`;
  return `<footer class="transport"><div class="transport-status"><span class="status-item ${!stopped&&!pending&&!failed?'green':''}">${icon('mic')}マイク ${label}</span>${!conference?`<span class="status-item ${!stopped&&!pending&&!failed?'green':''}">${icon('audio')}Mac音声 ${label}</span>`:''}<span class="status-item">${icon(conference?'shield':'cloud')}${conference?'オンデバイス':escapeHTML(cloudLabel())}</span><span class="mono">${conference?'08:42':'12:34'}</span></div><div class="transport-controls">${actions}</div></footer>`;
}
function evidence(){
  return `<div class="evidence"><span class="small">根拠となる発話</span><p>“The security review is still in progress.”</p>${button('11:48 · 相手側の発話を見る','evidence','link','clock')}</div>`;
}
function insight(){
  const aiUnavailable=!state.cloud||['ai-off','offline','reconnecting'].includes(state.scenario);
  if(aiUnavailable)return empty(state.scenario==='offline'?'AI提案を一時停止中':'AIを使わずに文字起こし中','発話は右側で確認できます。AIを利用する場合は、送信する内容を確認してください。','shield',state.scenario==='offline'?button('再接続する','reconnect'):button('送信内容を確認','cloud-consent'));
  if(['empty','no-insights'].includes(state.scenario)&&!state.askResult)return empty('必要なときに、提案が届きます','会話の質問や確認事項を検出すると、根拠と一緒に表示します。手動で質問することもできます。','sparkle');
  return `<article class="insight featured"><div class="row between"><span class="insight-kind">${icon('sparkle')}${state.askResult?'質問への回答案':'回答のヒント'}</span>${pill('要確認','amber')}</div><h2 class="insight-title">${state.askResult?'レビューの完了予定を、先に確認しましょう。':fixture.answer}</h2><p class="insight-copy">${fixture.reason}</p>${evidence()}<div class="card-footer"><span class="small muted">AIによる提案 · 発話を参照</span>${button('提案をコピー','copy','', 'document')}</div></article><article class="insight secondary-insight"><div class="row between"><span class="row">${icon('warning')}<span class="small">確認しておきたいこと</span></span><span class="small muted">12:18</span></div><h3>レビューの担当者は決まっていますか？</h3><p class="insight-copy">水曜の進捗確認までに、担当と完了条件を揃えておくと安心です。</p></article>`;
}
function timeline(){
  if(state.scenario==='empty')return empty('発話を待っています','音声が認識されると、自分と相手側を分けて表示します。','mic');
  return `<div class="timeline"><div class="timeline-header row between"><strong>会話の流れ</strong>${pill(`${escapeHTML(state.sourceLang)} / ${escapeHTML(state.remoteLang)}`,'neutral')}</div><div class="transcript-entry"><div class="transcript-meta"><span class="origin">${icon('mic')}自分 · マイク</span><time>11:32</time></div><p>まずは少人数のパイロットで、実際の利用状況を確認したいですね。</p></div><div class="transcript-entry"><div class="transcript-meta"><span class="origin">${icon('audio')}相手側 · Mac音声</span><time>11:48</time></div><p>${fixture.quote}</p></div><div class="transcript-entry highlight"><div class="transcript-meta"><span class="origin">${icon('audio')}相手側 · Mac音声</span><time>12:06</time></div><p>${fixture.question}</p></div>${!isInputStopped()?`<div class="transcript-entry partial"><div class="transcript-meta"><span class="origin">${icon('mic')}自分 · 認識中</span><span>•••</span></div><p>そうですね、まずレビューの…</p></div>`:''}<div class="timeline-foot"><span>人物名の自動識別は行いません</span>${button('全文','transcript','link')}</div></div>`;
}
function meeting(){
  const disabled=!state.cloud||['offline','ai-off','reconnecting','paused','stopping','stop-failed','disconnected','denied'].includes(state.scenario)||state.paused;
  return toolbar(`${button('AI送信','cloud-consent','','cloud')}${nav('小さく表示','floating','','compact')}`)+`<main class="main">${heading(escapeHTML(state.name),'会話を追いながら、次の一言を考える。',`${icon('meeting')} General · 自動保存オフ`,pill(isInputStopped()?'一時停止':'会議中',isInputStopped()?'neutral':'green',true))}${banner()}<div class="live-grid"><section><div class="section-heading"><h2>いま、役立つ提案</h2><small>発話をもとに生成</small></div>${insight()}<form id="ask-form" class="ask-bar">${icon('sparkle')}<input id="ask-input" aria-label="会話についてAIに質問" placeholder="この会話について質問する…" value="${escapeHTML(state.query)}" ${disabled?'disabled':''}><button class="primary" type="submit" aria-label="質問を送る" ${disabled?'disabled':''}>${icon('arrow')}</button></form><p class="ask-hint">${disabled?'AI送信は停止中です。':'送信対象：質問と直近の確定発話。音声は送りません。'}</p></section><aside aria-label="会話の文字起こし">${timeline()}</aside></div></main>`+transport();
}
function recentRows(rows=state.sessions){return `<div class="session-list">${rows.map(s=>`<div class="session-row"><span class="session-icon">${icon(s.type==='Meeting'?'meeting':'captions')}</span><div class="grow"><h3>${escapeHTML(s.name)}</h3><p>${s.type} · ${s.date} · ${s.duration} · このMacに保存</p></div>${button('開く',`open-session:${s.id}`,'ghost','arrow')}${state.screen==='sessions'?button('削除',`delete-session:${s.id}`,'ghost','trash'):''}</div>`).join('')}</div>`;}
function home(){return toolbar()+`<main class="main"><div class="welcome">${heading('会話に、集中できる場所。','字幕を読むときも、次の一言を考えるときも。','ConfLingo')}<div class="mode-cards"><article class="mode-card"><span class="mode-icon">${icon('captions')}</span><h2>Conference</h2><p>聞きながら、原文と翻訳を読む。<br>講演やセッションの理解を支えます。</p>${nav('字幕をはじめる','conference-setup','primary large','arrow')}</article><article class="mode-card"><span class="mode-icon">${icon('meeting')}</span><h2>Meeting</h2><p>会話の文脈から、回答や確認のヒントを。<br>発話の根拠を確かめながら使えます。</p>${nav('会議を準備する','preparation','large','arrow')}</article></div><section class="recent"><div class="section-heading"><h2>最近保存したセッション</h2>${nav('すべて見る','sessions','link')}</div>${state.scenario==='empty'||!state.sessions.length?empty('まだ保存したセッションはありません','明示的に保存した会議や字幕だけが、ここに表示されます。','folder'):recentRows()}</section></div></main>`;}
function langOptions(selected,values=['日本語','English']){return values.map(v=>`<option ${v===selected?'selected':''}>${v}</option>`).join('');}
function privacy(){return `<aside class="panel"><h2>この会議で扱うデータ</h2><div class="privacy-summary"><div class="row">${icon('mic')}<div><strong>音声は、このMacで処理</strong>マイクとMacの出力音声を文字起こし。音声ファイルは保存しません。</div></div><div class="row">${icon('cloud')}<div><strong>クラウドAIは任意</strong>許可した場合だけ、質問・必要な確定発話・会話の要約を送ります。</div></div><div class="row">${icon('folder')}<div><strong>保存は、会議のあとで</strong>終了後に保存か破棄を選べます。自動保存はオフです。</div></div></div></aside>`;}
function preparation(){return toolbar()+`<main class="main">${heading('会議の準備','入力と共有範囲を確認してから、はじめましょう。','Meeting / 01 準備 → 02 会議 → 03 振り返り')}${banner()}<div class="form-layout"><section class="panel"><div class="field"><label for="meeting-name">会議名</label><input id="meeting-name" value="${escapeHTML(state.name)}" placeholder="例：プロダクト定例"></div><hr class="form-separator"><h2>音声入力</h2><div class="input-source">${icon('mic')}<div class="grow"><strong>自分 · マイク</strong><small>MacBook Proのマイク</small></div><label class="field"><span class="small">認識言語</span><select id="source-language">${langOptions(state.sourceLang)}</select></label></div><div class="input-source">${icon('audio')}<div class="grow"><strong>相手側 · Macの音声</strong><small>会議アプリ以外の出力音声も含みます</small></div><label class="field"><span class="small">認識言語</span><select id="remote-language">${langOptions(state.remoteLang)}</select></label></div><p class="small muted">回り込みを抑えるため、ヘッドフォンでの利用をおすすめします。</p><hr class="form-separator"><label class="check-row"><input id="consent" type="checkbox" ${state.consent?'checked':''}><span>参加者へ音声取得を通知し、必要な同意を確認しました<small>このチェックで通知が送信されることはありません。</small></span></label><hr class="form-separator"><label class="check-row"><input id="cloud-enable" type="checkbox" ${state.cloud?'checked':''}><span>この会議でクラウドAIを使う<small>必要な確定発話と要約を外部AIへ送ることを許可します。音声は送りません。</small></span></label><div class="spacer"></div>${button('参照資料と送信範囲','knowledge','link','book')}<div class="form-actions"><small id="start-reason">${state.consent?'Generalプリセットで開始します。':'開始するには、参加者への通知・同意を確認してください。'}</small>${button('会議を開始','meeting-start','primary large','play',(!state.consent||['permission','preparing','denied'].includes(state.scenario))?'disabled aria-describedby="start-reason"':'')}</div></section>${privacy()}</div></main>`;}
function conferenceSetup(){return toolbar()+`<main class="main">${heading('字幕の準備','聴きたい言語と、読みたい言語を選びます。','Conference')}${banner()}<div class="form-layout"><section class="panel"><div class="fields"><label class="field full"><span>セッション名</span><input id="conference-name" value="${escapeHTML(state.conferenceName)}"></label><label class="field"><span>認識する言語</span><select id="conference-source">${langOptions(state.source,['English (US)','日本語','Deutsch','Français'])}</select></label><label class="field"><span>翻訳先</span><select id="conference-target" ${state.only?'disabled':''}>${langOptions(state.target,['日本語','English','Deutsch','Français'])}</select></label><label class="check-row field full"><input id="only" type="checkbox" ${state.only?'checked':''}><span>文字起こしのみ<small>翻訳せず、原文の字幕だけを表示します。</small></span></label>${state.only?`<label class="check-row field full"><input id="fast" type="checkbox" ${state.fast?'checked':''}><span>高速確定を使う<small>精度より字幕の速さを優先します。</small></span></label>`:''}</div><hr class="form-separator"><div class="row between"><div><h3>専門用語辞書</h3><p class="small muted">固有名詞や訳語を、いつもの表記で。</p></div>${button('辞書を管理','dictionary','','book')}</div><div class="spacer"></div><label class="field"><span>使用する辞書</span><select id="profile">${state.profiles.map((p,i)=>`<option value="${i}" ${state.profile===i?'selected':''}>${escapeHTML(p.name)}</option>`).join('')}</select></label><div class="spacer"></div><p class="small muted">${escapeHTML(state.profiles[state.profile].terms||'登録された用語はありません')}</p><div class="form-actions"><small>音声認識と翻訳はこのMacで行います。</small>${button('字幕を開始','conference-start','primary large','play',['permission','preparing','denied'].includes(state.scenario)?'disabled':'')}</div></section><aside class="panel"><h2>読むことに、集中。</h2><p class="privacy-summary">原文と翻訳を並べて表示します。字幕の文字サイズ、最前面表示は、いつでも変更できます。</p><hr class="form-separator"><div class="row between"><span class="small">開始 / 停止</span><span class="key">⌘ R</span></div><div class="spacer"></div><div class="row between"><span class="small">文字を拡大 / 縮小</span><span class="key">⌘ ＋ / −</span></div><p class="subtitle">対応言語は、Macで利用できるモデルに応じて表示されます。</p></aside></div></main>`;}
function conference(){
  const only=state.only;
  const original=`<div class="caption-block"><time>08:12</time><p>Great tools help us stay present in the conversation, without getting in the way.</p></div><div class="caption-block"><time>08:27</time><p>With on-device speech recognition, we can turn spoken words into useful context while keeping audio on the Mac.</p></div>${state.conferenceRunning?'<div class="caption-block partial"><small>認識中</small><p>And that gives us a different way to think about…</p></div>':''}`;
  const translated=`<div class="caption-block"><time>08:12</time><p>優れた道具は、会話の妨げにならず、その場に集中する手助けをします。</p></div><div class="caption-block"><time>08:27</time><p>${state.scenario==='translation-failed'?'この部分を翻訳できませんでした。原文をご確認ください。':'オンデバイスの音声認識を使えば、音声をMacに保ったまま、話し言葉を役立つ文脈に変えることができます。'}</p></div>${state.conferenceRunning?'<div class="caption-block partial"><small>翻訳待ち</small><p>次の発話が確定するのを待っています。</p></div>':''}`;
  return toolbar(`${button('A−','smaller','','','aria-label="字幕を小さく"')}${button('A＋','larger','','','aria-label="字幕を大きく"')}${button('最前面','pin','','pin',`aria-pressed="${state.pinned}"`)}${button('書き出す','export','','export',state.scenario==='empty'?'disabled':'')}`)+`<main class="main">${heading(escapeHTML(state.conferenceName),`${escapeHTML(state.source)} ${only?'· 文字起こしのみ':`→ ${escapeHTML(state.target)}`} · 辞書：${escapeHTML(state.profiles[state.profile].name)}`,'Conference',button('字幕の設定','conference-settings','','settings'))}${banner()}${state.scenario==='empty'?empty('音声を待っています','開始すると、この場所に原文と翻訳が表示されます。','mic'):`<div class="conference-grid" ${only?'style="grid-template-columns:1fr"':''}><section class="caption-pane"><h2>原文 · ${escapeHTML(state.source)} ${pill('オンデバイス','green')}</h2>${original}</section>${!only?`<section class="caption-pane"><h2>翻訳 · ${escapeHTML(state.target)} <span class="small muted">文ごとに翻訳</span></h2>${translated}</section>`:''}</div>`}<div class="row between" style="margin-top:18px"><span class="small muted">字幕を選択してコピーできます。</span>${button('字幕を消去','clear','ghost','trash',state.conferenceRunning||['stopping','stop-failed'].includes(state.scenario)?'disabled':'')}</div></main>`+transport(true);
}
function candidate(kind){
  const status=state.decisions[kind],decision=kind==='decision';
  const title=decision?'パイロット公開日は、レビュー完了を条件に判断する':'水曜までにセキュリティレビューの進捗を確認する';
  const text=decision?'公開日はまだ確定していません。条件と関係者の合意を確認してください。':'担当者：未確定 · 期限：水曜（具体的な日付は要確認）';
  return `<article class="candidate"><div class="row between">${pill(status==='suggested'?(decision?'決定候補':'アクション候補'):status==='acknowledged'?'確認済み':'却下済み',status==='acknowledged'?'green':status==='suggested'?'amber':'neutral')}<span class="small muted">AIが抽出</span></div><h3>${title}</h3><p>${text}</p><div class="row between">${button('根拠 · 11:48 / 12:06','evidence','link','clock')}<span class="row">${status==='suggested'?`${button('却下',`dismiss:${kind}`,'ghost')}${button('内容を確認',`confirm:${kind}`,'','check')}`:button('候補に戻す',`reset:${kind}`,'ghost')}</span></div></article>`;
}
function review(){return toolbar(`${button('Markdownを書き出す','export','','export')}`)+`<main class="main">${heading('会議を、次につなげる。',`${escapeHTML(state.name)} · 2026年11月8日`,'Meeting / 振り返り',pill(state.saved?'このMacに保存済み':'まだ保存されていません',state.saved?'green':'amber'))}<div class="review-stats"><div><strong>12:34</strong><small>会議時間</small></div><div><strong>2</strong><small>音声入力</small></div><div><strong>${Object.values(state.decisions).filter(v=>v==='acknowledged').length}</strong><small>確認済みの候補</small></div></div>${state.scenario==='empty'?empty('確認する候補はありません','発話がない会議は保存せずに終了できます。','document',button('保存せず終了','discard')):`<div class="live-grid"><section><div class="section-heading"><h2>決定と、次のアクション</h2><small>自動では確定しません</small></div>${candidate('decision')}${candidate('action')}<div class="form-actions">${button('保存せず終了','discard','ghost')}${button(state.saved?'保存済み':'このMacに保存','save','primary','folder',state.saved?'disabled':'')}</div></section><aside class="panel"><h2>会話の要点</h2><p class="insight-copy">少人数のパイロット実施を検討しました。公開日を判断するには、進行中のセキュリティレビューの状況確認が必要です。</p><div class="evidence">AIによる要約です。元の発話と照らし合わせて確認してください。</div><div class="spacer"></div>${button('会話の全文を読む','transcript','link','captions')}<hr class="form-separator"><p class="small muted">音声取得・AI送信は停止しています。書き出し先のMarkdownは、アプリ内の保存とは別に管理されます。</p></aside></div>`}</main>`;}
function sessions(){
  const rows=state.sessions.filter(s=>s.name.toLowerCase().includes(state.search.toLowerCase()));
  return toolbar()+`<main class="main">${heading('保存したセッション','このMacに明示的に保存した会議と字幕。','ライブラリ')}<div class="row between" style="margin-bottom:24px"><label class="row">${icon('search')}<input class="search" id="session-search" aria-label="保存したセッションを検索" placeholder="セッション名で検索" value="${escapeHTML(state.search)}"></label><span class="small muted">自動保存はオフ</span></div>${state.scenario==='empty'||!rows.length?empty('表示するセッションがありません',state.search?'別の名前で検索してください。':'保存した会議と字幕がここに表示されます。','folder'):recentRows(rows)}</main>`;
}
function settings(){return toolbar()+`<main class="main">${heading('設定','入力、表示、データの扱いを整える。','ConfLingo')}<div class="settings-grid"><section class="panel"><h2>音声と言語</h2><div class="setting-row"><div><h3>入力の確認</h3><p>会議の前に、入力元と言語を確認します。</p></div>${nav('会議の準備へ','preparation')}</div><div class="setting-row"><div><h3>専門用語辞書</h3><p>認識する語句と、翻訳時の表記を管理。</p></div>${button('管理する','dictionary','','book')}</div></section><section class="panel"><h2>プライバシー</h2><div class="setting-row"><div><h3>クラウドAI</h3><p>初期設定はオフ。会議ごとに送信を許可します。</p></div>${pill('会議ごとに確認','neutral')}</div><div class="setting-row"><div><h3>音声ファイル</h3><p>保存せず、文字起こしに使用します。</p></div>${pill('保存しない','green')}</div><div class="setting-row"><div><h3>セッションの保持</h3><p>終了後に保存か破棄を選びます。</p></div>${pill('自動保存オフ','neutral')}</div><div class="setting-row"><div><h3>資料の外部送信</h3><p>会議ごとの許可なしに送信しません。</p></div>${button('範囲を確認','knowledge')}</div></section><section class="panel"><h2>表示と操作</h2><div class="setting-row"><div><h3>配色</h3><p>明るい場所でも、暗い場所でも。</p></div><label><span class="hidden">配色</span><select id="settings-theme">${langOptions(state.theme,['light','dark'])}</select></label></div><div class="setting-row"><div><h3>字幕の開始 / 停止</h3><p>Conferenceの既存操作を引き継ぎます。</p></div><span class="key">⌘ R</span></div><div class="setting-row"><div><h3>字幕の文字サイズ</h3><p>10〜48pt。字幕画面からも調整できます。</p></div><span class="key">⌘ ＋ / −</span></div></section></div></main>`;}
function floating(){
  const inactive = !state.cloud||['ai-off','offline','no-insights'].includes(state.scenario);
  return toolbar(nav('会議を展開','meeting','','expand'))+`<main class="floating-stage"><div class="floating-caption">会議アプリのそばに。必要な提案を、ひとつだけ。</div>${state.hidden?empty('小窓を非表示にしました','非表示でも、収集を停止するまでは文字起こしが続きます。','eye',button('小窓を再表示（モック）','show-floating','primary')):`<section class="floating-panel" aria-label="Meeting フローティングパネル"><div class="floating-top"><span class="row">${icon('captions')}<strong>ConfLingo</strong><span class="muted mono">12:34</span></span><span class="row">${nav('','meeting','icon-button','expand').replace('<button','<button aria-label="会議を展開"')}${button('','hide-floating','icon-button','close','aria-label="小窓を非表示"')}</span></div><div class="floating-content">${banner()}<span class="insight-kind">${icon('sparkle')}${inactive?'会話を文字起こし中':'回答のヒント'}</span><h2>${inactive?'必要なときに、会話を確認。':fixture.answer}</h2>${inactive?'<p class="small muted">新しいAI提案はありません。会話の全文は展開して確認できます。</p>':`<span class="small muted">AIによる提案 · 要確認</span><div class="evidence">${button('根拠 · 11:48 相手側','evidence','link','clock')}</div>`}</div><div class="floating-bottom"><div class="row between" style="margin-bottom:10px"><span class="small muted">${isInputStopped()?'音声収集 停止中':'マイク + Mac音声 取得中'}</span><span class="small muted">${escapeHTML(cloudLabel())}</span></div><div class="row">${state.scenario==='stop-failed'?button('停止を再試行','retry-stop','danger'):state.scenario==='stopping'?button('終了処理中…','noop','','','disabled'):`${button(isInputStopped()?'再開':'収集を一時停止',isInputStopped()?'resume':'pause','','pause')}${button('AI停止','cloud-off','','cloud',!state.cloud?'disabled':'')}${button('終了','end','danger','stop')}`}</div></div></section>`}<p class="floating-caption">画面共有に映る場合があります。共有前に表示を確認してください。</p></main>`;
}
function render(){
  const screens={home,preparation,meeting,conference,'conference-setup':conferenceSetup,review,sessions,settings,floating};
  app.innerHTML=sidebar()+`<div class="workspace">${screens[state.screen]()}</div>`;
  document.body.dataset.theme=state.theme;
  document.documentElement.style.setProperty('--scale',state.scale);
  document.documentElement.style.setProperty('--caption',`${state.captionSize}px`);
  document.querySelector('#screen-picker').value=state.screen;
  document.querySelector('#state-picker').innerHTML=availableStates[state.screen].map(s=>`<option value="${s}" ${state.scenario===s?'selected':''}>${scenarios[s]}</option>`).join('');
  document.querySelector('#theme-picker').value=state.theme;
  document.querySelector('#scale-picker').value=String(state.scale);
  history.replaceState(null,'',`#${state.screen}`);
}
function showScreen(screen,{preview=false}={}){
  state.screen=screen;state.scenario='normal';state.hidden=false;
  if(preview){state.paused=false;state.cloud=['meeting','floating'].includes(screen);state.meetingActive=['meeting','floating'].includes(screen);state.conferenceRunning=screen==='conference';state.askResult=false;}
  render();
  document.querySelector('h1')?.setAttribute('tabindex','-1');
  document.querySelector('h1')?.focus({preventScroll:true});
}
function toast(message){const el=document.querySelector('#toast');el.textContent=message;el.classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>el.classList.remove('visible'),3500);}
function openDialog(title,body,actions=button('閉じる','close-dialog')){
  dialogOrigin=document.activeElement;
  dialog.innerHTML=`<h2 id="dialog-title">${title}</h2>${body}<div class="dialog-actions">${actions}</div>`;
  dialog.showModal();
}
function closeDialog(){dialog.close();if(dialogOrigin?.isConnected)dialogOrigin.focus();}
function confirmation(title,text,action,label='続ける'){
  openDialog(title,`<p>${text}</p>`,`${button('キャンセル','close-dialog')}${button(label,action,'primary')}`);
}
function dictionary(){
  const p=state.profiles[state.profile];
  openDialog('専門用語辞書',`<label class="field"><span>辞書の名前</span><input id="dictionary-name" value="${escapeHTML(p.name)}"></label><label class="field"><span>専門用語・固定訳語</span><textarea id="dictionary-terms">${escapeHTML(p.terms)}</textarea><small>カンマで区切ります。例：evals=評価。訳語を省略すると原文表記を保持します。</small></label><div class="row" style="margin-top:20px">${button('新規作成','dictionary-new')}${button('複製','dictionary-duplicate')}${button('削除','dictionary-delete','danger','trash',state.profiles.length<=1?'disabled':'')}</div>`,`${button('キャンセル','close-dialog')}${button('変更を反映','dictionary-save','primary')}`);
}
function exportMarkdown(){
  const meetingExport=['review','meeting','floating'].includes(state.screen);
  const text=meetingExport?`# ${state.name}\n\n> PR5-Aレビュー用の架空データ。製品の保存形式ではありません。\n\n## 会話\n\n11:48 相手側: ${fixture.quote}\n\n12:06 相手側: ${fixture.question}\n\n## 候補\n\n- [${state.decisions.decision==='acknowledged'?'確認済み':state.decisions.decision==='dismissed'?'却下':'未確認'}] 公開日はレビュー完了を条件に判断する\n- [${state.decisions.action==='acknowledged'?'確認済み':state.decisions.action==='dismissed'?'却下':'未確認'}] 水曜に進捗確認（担当・日付は要確認）\n`:`# ${state.conferenceName}\n\n> PR5-Aレビュー用の架空データ。現行Markdown互換性の検証用ではありません。\n\nGreat tools help us stay present in the conversation, without getting in the way.\n${state.only?'':'\n優れた道具は、会話の妨げにならず、その場に集中する手助けをします。\n'}`;
  const url=URL.createObjectURL(new Blob([text],{type:'text/markdown;charset=utf-8'}));
  const link=document.createElement('a');link.href=url;link.download='ConfLingo-design-sample.md';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);toast('レビュー用のサンプルMarkdownを書き出しました');
}
function route(screen){
  if(['stopping','stop-failed'].includes(state.scenario)){
    openDialog('停止の完了を待ってください','<p>停止処理が完了するまで画面を切り替えられません。停止失敗の場合は元の画面で再試行してください。</p>');return;
  }
  if(state.meetingActive||state.conferenceRunning){confirmation('進行中のセッションを終了しますか？','別の画面へ移る前に音声収集を止めます。会議の発話は振り返り画面で確認してください。',`route-confirm:${screen}`,'停止して移動');return;}
  showScreen(screen);
}
function handleAction(action){
  const [name,arg]=action.split(':');
  switch(name){
    case 'close-dialog':closeDialog();return;
    case 'noop':return;
    case 'meeting-start':if(!state.consent)return;state.meetingActive=true;state.paused=false;state.askResult=false;state.saved=false;state.decisions={decision:'suggested',action:'suggested'};showScreen('meeting');toast('会議開始のシミュレーションです。音声は取得しません');return;
    case 'conference-start':state.conferenceRunning=true;state.paused=false;showScreen('conference');return;
    case 'conference-stop':state.conferenceRunning=false;state.scenario='paused';state.paused=true;break;
    case 'pause':state.paused=true;state.scenario='paused';break;
    case 'resume':state.paused=false;state.scenario='normal';if(state.screen==='conference')state.conferenceRunning=true;else state.meetingActive=true;break;
    case 'end':confirmation('会議を終了しますか？','音声収集とAI送信を止め、振り返りへ進みます。ここまでの発話は確認できます。','end-confirm','終了して振り返る');return;
    case 'end-confirm':closeDialog();state.meetingActive=false;state.paused=false;state.cloud=false;state.sharingDocs=false;showScreen('review');return;
    case 'retry-stop':state.meetingActive=false;state.conferenceRunning=false;state.paused=false;state.cloud=false;state.sharingDocs=false;state.scenario='normal';if(state.screen==='conference'){toast('停止成功の表示例です');break;}showScreen('review');toast('停止成功後の遷移例です');return;
    case 'route-confirm':closeDialog();state.meetingActive=false;state.conferenceRunning=false;state.paused=false;state.cloud=false;state.sharingDocs=false;showScreen(arg);toast('停止後の画面移動を再現しました');return;
    case 'cloud-off':state.cloud=false;state.scenario='ai-off';break;
    case 'cloud-consent':openDialog('クラウドAIへの送信',`<p>質問、必要な確定発話、会話の短い要約を外部AIへ送ります。音声ファイルは送りません。</p><p>資料の抜粋は、資料送信を別途許可した場合だけ対象になります。</p><p class="small">この会議の許可は、会議終了時に解除されます。</p>`,`${button('閉じる','close-dialog')}${state.cloud?button('クラウドAIを停止','cloud-disable-dialog','danger'):button('この会議で許可','cloud-allow','primary')}`);return;
    case 'cloud-allow':closeDialog();state.cloud=true;if(['ai-off','offline','reconnecting'].includes(state.scenario))state.scenario='normal';break;
    case 'cloud-disable-dialog':closeDialog();state.cloud=false;state.scenario='ai-off';break;
    case 'reconnect':state.scenario='normal';toast('AI再接続成功の表示例です。実通信は行いません');break;
    case 'grant':state.scenario='normal';toast('権限許可後の表示例です。OSへの権限要求は行いません');break;
    case 'cancel-preparation':state.scenario='normal';state.conferenceRunning=false;state.meetingActive=false;showScreen(state.screen.startsWith('conference')?'conference-setup':'preparation');return;
    case 'permission-help':openDialog('音声アクセスを確認する',`<p>システム設定のプライバシーとセキュリティから、ConfLingoのマイクと画面・システムオーディオの許可を確認します。</p><p>設定を変更した後、入力を再確認してください。</p>`,`${button('閉じる','close-dialog')}${button('許可後の表示を見る','permission-resolved','primary')}`);return;
    case 'permission-resolved':closeDialog();state.scenario='normal';state.conferenceRunning=false;state.meetingActive=false;showScreen(state.screen.startsWith('conference')?'conference-setup':'preparation');return;
    case 'input-help':openDialog('入力を確認して再開',`<p>マイクの接続とMacの音声出力を確認してください。復帰後に同じ会議の収集を再開します。</p>`,`${button('閉じる','close-dialog')}${button('復帰後の表示を見る','input-resolved','primary')}`);return;
    case 'input-resolved':closeDialog();handleAction('resume');return;
    case 'evidence':openDialog('提案の根拠',`<div class="row">${pill('相手側 · Mac音声','blue')}<span class="small muted">11:48 · 確定した発話</span></div><blockquote>${fixture.quote}</blockquote><p>12:06では、来週金曜のパイロット公開が可能か質問されています。</p><blockquote>${fixture.question}</blockquote><p>「水曜に進捗確認」は「水曜にレビュー完了」を意味しません。公開日は未確定です。</p>`);return;
    case 'transcript':openDialog('会話の全文',`<p>架空の会議サンプル · 自動話者識別なし</p>${timeline()}`);return;
    case 'copy':navigator.clipboard?.writeText(fixture.answer).then(()=>toast('提案をコピーしました')).catch(()=>toast('コピーできません。提案の文章を選択してコピーしてください'));return;
    case 'pin':state.pinned=!state.pinned;toast('最前面表示の選択状態を再現しました。OSのウィンドウ階層は変更しません');break;
    case 'larger':state.captionSize=Math.min(48,state.captionSize+2);break;
    case 'smaller':state.captionSize=Math.max(10,state.captionSize-2);break;
    case 'conference-settings':if(state.conferenceRunning){confirmation('字幕を停止して設定を変更しますか？','ここまでの字幕は保持します。言語や辞書を変更したあと再開できます。','conference-settings-confirm','停止して設定へ');return;}showScreen('conference-setup');return;
    case 'conference-settings-confirm':closeDialog();state.conferenceRunning=false;state.paused=false;showScreen('conference-setup');return;
    case 'clear':confirmation('字幕を消去しますか？','このセッションの字幕を消去します。書き出し済みのMarkdownは削除しません。','clear-confirm','消去する');return;
    case 'clear-confirm':closeDialog();state.scenario='empty';break;
    case 'dictionary':dictionary();return;
    case 'dictionary-save':{const n=document.querySelector('#dictionary-name').value.trim();if(!n){toast('辞書の名前を入力してください');return;}state.profiles[state.profile]={name:n,terms:document.querySelector('#dictionary-terms').value};closeDialog();toast('モック内の辞書を更新しました');break;}
    case 'dictionary-new':closeDialog();state.profiles.push({name:'新しい辞書',terms:''});state.profile=state.profiles.length-1;render();dictionary();return;
    case 'dictionary-duplicate':closeDialog();state.profiles.push({...state.profiles[state.profile],name:state.profiles[state.profile].name+' のコピー'});state.profile=state.profiles.length-1;render();dictionary();return;
    case 'dictionary-delete':if(state.profiles.length<=1)return;closeDialog();confirmation('この辞書を削除しますか？','削除した辞書はモック内で元に戻せません。','dictionary-delete-confirm','削除する');return;
    case 'dictionary-delete-confirm':closeDialog();state.profiles.splice(state.profile,1);state.profile=0;break;
    case 'knowledge':openDialog('参照資料と送信範囲',`<p>会議に必要な資料だけを参照します。外部AIへの送信範囲は、会議ごとに選べます。</p><div class="evidence"><strong>pilot-checklist.md</strong><p>「パイロット前に、セキュリティレビューの完了を確認する。」</p><span class="small">レビュー用の架空資料 · 3行目</span></div><label class="check-row"><input id="document-consent" type="checkbox" ${state.sharingDocs?'checked':''}><span>この会議に限り、必要な抜粋をAIへ送る<small>クラウドAIが有効なときだけ適用します。</small></span></label>`,`${button('閉じる','close-dialog')}${button('選択を反映','knowledge-save','primary')}`);return;
    case 'knowledge-save':state.sharingDocs=document.querySelector('#document-consent').checked;closeDialog();toast('資料送信の選択をモック内に反映しました');return;
    case 'confirm':openDialog('候補の内容を確認',`<p>${arg==='decision'?'レビュー完了を条件に公開日を判断する、という内容を確認済みにします。公開日そのものは確定しません。':'水曜に進捗を確認する候補です。担当者と具体的な日付は未確定のまま残ります。'}</p><p>関係者との合意と、根拠の発話を確認してください。</p>`,`${button('キャンセル','close-dialog')}${button('この内容を確認済みにする',`acknowledge:${arg}`,'primary')}`);return;
    case 'acknowledge':closeDialog();state.decisions[arg]='acknowledged';break;
    case 'dismiss':state.decisions[arg]='dismissed';break;
    case 'reset':state.decisions[arg]='suggested';break;
    case 'save':state.saved=true;if(!state.sessions.some(s=>s.id===3))state.sessions.unshift({id:3,name:state.name,type:'Meeting',date:'11月8日',duration:'12分'});toast('モック内で保存状態にしました。リロードすると初期化されます');break;
    case 'discard':confirmation('保存せずに終了しますか？','この会議の未保存の内容を破棄します。書き出したMarkdownは残ります。','discard-confirm','破棄して終了');return;
    case 'discard-confirm':closeDialog();state.saved=false;state.decisions={decision:'suggested',action:'suggested'};showScreen('home');toast('未保存内容の破棄を再現しました');return;
    case 'export':exportMarkdown();return;
    case 'open-session':{const s=state.sessions.find(s=>s.id===Number(arg));if(s.type==='Conference'){state.conferenceName=s.name;state.conferenceRunning=false;state.paused=false;showScreen('conference');}else{state.name=s.name;state.saved=true;showScreen('review');}return;}
    case 'delete-session':confirmation('保存したセッションを削除しますか？','このMacに保存した会話と候補を削除します。書き出したMarkdownは残ります。',`delete-confirm:${arg}`,'削除する');return;
    case 'delete-confirm':closeDialog();state.sessions=state.sessions.filter(s=>s.id!==Number(arg));toast('モック内のセッションを削除しました');break;
    case 'hide-floating':state.hidden=true;break;
    case 'show-floating':state.hidden=false;break;
  }
  render();
}
document.addEventListener('click',event=>{
  const target=event.target.closest('button');if(!target||target.disabled)return;
  if(target.dataset.action)handleAction(target.dataset.action);
  if(target.dataset.nav){
    const preserve=['meeting','floating'].includes(state.screen)&&['meeting','floating'].includes(target.dataset.nav);
    const previous=state.scenario;showScreen(target.dataset.nav);if(preserve){state.scenario=previous;render();}
  }
  if(target.dataset.route)route(target.dataset.route);
});
document.addEventListener('change',event=>{
  const el=event.target;
  if(el.id==='screen-picker'){showScreen(el.value,{preview:true});return;}
  if(el.id==='state-picker'){
    state.scenario=el.value;state.paused=el.value==='paused';state.askResult=false;
    if(el.value==='ai-off')state.cloud=false;
    else if(['meeting','floating'].includes(state.screen))state.cloud=true;
    render();return;
  }
  const map={'theme-picker':'theme','settings-theme':'theme','scale-picker':'scale','source-language':'sourceLang','remote-language':'remoteLang','conference-source':'source','conference-target':'target','profile':'profile'};
  if(map[el.id])state[map[el.id]]=['scale-picker','profile'].includes(el.id)?Number(el.value):el.value;
  const checks={consent:'consent','cloud-enable':'cloud',only:'only',fast:'fast'};
  if(checks[el.id])state[checks[el.id]]=el.checked;
  if(map[el.id]||checks[el.id]){const id=el.id;render();document.getElementById(id)?.focus({preventScroll:true});}
});
document.addEventListener('input',event=>{
  const el=event.target;
  const map={'meeting-name':'name','conference-name':'conferenceName','ask-input':'query'};
  if(map[el.id])state[map[el.id]]=el.value;
  if(el.id==='session-search'){state.search=el.value;const start=el.selectionStart;render();const input=document.querySelector('#session-search');input.focus();input.setSelectionRange(start,start);}
});
document.addEventListener('submit',event=>{
  if(event.target.id!=='ask-form')return;
  event.preventDefault();if(!state.query.trim()){toast('質問を入力してください');document.querySelector('#ask-input').focus();return;}
  state.askResult=true;state.query='';render();toast('サンプルの回答案を表示しました。AIへは送信していません');document.querySelector('#ask-input').focus();
});
dialog.addEventListener('cancel',()=>{if(dialogOrigin?.isConnected)dialogOrigin.focus();});
const initial=location.hash.slice(1);
if(Object.hasOwn(labels,initial))state.screen=initial;
state.cloud=['meeting','floating'].includes(state.screen);
state.meetingActive=['meeting','floating'].includes(state.screen);
state.conferenceRunning=state.screen==='conference';
render();
