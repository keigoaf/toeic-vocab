/* ====================================================================
   TOEIC 単語トレーナー Service Worker
   最終更新日時: 2026-07-23 10:10 (JST)  /  対応アプリ版: v1.8.0
   --------------------------------------------------------------------
   【役割】
     アプリ本体をキャッシュしてオフライン起動を可能にしつつ、
     オンライン時は必ず最新版に切り替わるようにする。

   【v1.8.0 での変更理由】
     iOSのホーム画面アプリ(スタンドアロンPWA)で、古いキャッシュが
     返され続けてアプリが更新されない問題が起きた。
     引っぱって更新もできず、再起動でも直らないため、以下を実施:
       1. HTMLとJSONは常にネットワークを優先し、取得できたら
          即キャッシュを差し替える（stale厳禁）。
       2. index.html の取得時は cache:'reload' でHTTPキャッシュも迂回。
       3. install で skipWaiting、activate で clients.claim を行い、
          新しいSWが即座に制御を奪う（待機状態で止まらない）。
       4. ページ側からの 'SKIP_WAITING' メッセージに対応し、
          更新検知時に即時反映できるようにする。
   【更新手順】
     ファイルを更新したら必ず下の CACHE のバージョンを上げること。
     activate で旧キャッシュが削除され、確実に入れ替わる。
   ==================================================================== */
const CACHE = 'toeic-vocab-v1.8.0';

/* オフライン起動に必要な最小限のファイル */
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './toeic-500.json',
  './toeic-1000.json',
  './icon-192.png',
  './icon-512.png',
  './icon-180.png',
  './icon-maskable-512.png'
];

/* インストール: 事前キャッシュし、待機せず即座に有効化する */
self.addEventListener('install', (e)=>{
  e.waitUntil((async ()=>{
    const c = await caches.open(CACHE);
    // cache:'reload' でHTTPキャッシュを迂回し、必ずサーバから取り直す
    await Promise.all(ASSETS.map(async (url)=>{
      try{
        const res = await fetch(new Request(url, { cache: 'reload' }));
        if(res && res.ok) await c.put(url, res);
      }catch(err){ /* 個別の失敗は無視（オフライン等） */ }
    }));
    await self.skipWaiting();   // 待機せずすぐ次の版へ
  })());
});

/* 有効化: 旧キャッシュを削除し、開いている全ページの制御を即座に奪う */
self.addEventListener('activate', (e)=>{
  e.waitUntil((async ()=>{
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

/* ページ側から更新を促されたら即座に切り替える */
self.addEventListener('message', (e)=>{
  if(e.data === 'SKIP_WAITING') self.skipWaiting();
});

/* 取得戦略:
   - HTML / JSON → ネットワーク優先（常に最新を取る）。失敗時のみキャッシュ。
   - それ以外(画像など) → キャッシュ優先（変化しないので高速に）。 */
self.addEventListener('fetch', (e)=>{
  const req = e.request;
  if(req.method !== 'GET') return;

  const url = new URL(req.url);
  if(url.origin !== self.location.origin) return;   // 外部リソースは触らない

  const isDoc  = req.mode === 'navigate' || req.destination === 'document';
  const isData = url.pathname.endsWith('.json');

  if(isDoc || isData){
    // ネットワーク優先。HTTPキャッシュも迂回して確実に最新を取る。
    e.respondWith((async ()=>{
      try{
        const res = await fetch(new Request(req, { cache: 'no-store' }));
        if(res && res.ok){
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy)).catch(()=>{});
        }
        return res;
      }catch(err){
        const cached = await caches.match(req);
        return cached || await caches.match('./index.html');
      }
    })());
    return;
  }

  // 画像等: キャッシュ優先、無ければ取得してキャッシュ
  e.respondWith((async ()=>{
    const cached = await caches.match(req);
    if(cached) return cached;
    try{
      const res = await fetch(req);
      if(res && res.ok){
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy)).catch(()=>{});
      }
      return res;
    }catch(err){
      return caches.match('./index.html');
    }
  })());
});
