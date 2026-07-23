/* ====================================================================
   TOEIC 単語トレーナー Service Worker
   最終更新日時: 2026-07-23 09:20 (JST)  /  対応アプリ版: v1.5.0
   --------------------------------------------------------------------
   役割:
     - アプリ本体（index.html）とアイコンをキャッシュし、オフラインでも
       起動できるようにする。
     - 方針は「ネットワーク優先 + キャッシュ退避」。オンライン時は常に
       最新を取得しつつキャッシュも更新、オフライン時はキャッシュで動く。
   更新時の注意:
     - index.html 等を更新したら、下の CACHE 名のバージョンを上げること。
       古いキャッシュが activate 時に削除され、確実に入れ替わる。
   ==================================================================== */
const CACHE = 'toeic-vocab-v1.5.0';
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

/* インストール: アプリシェルを事前キャッシュ */
self.addEventListener('install', (e)=>{
  e.waitUntil(
    caches.open(CACHE).then((c)=> c.addAll(ASSETS)).then(()=> self.skipWaiting())
  );
});

/* 有効化: 旧バージョンのキャッシュを掃除 */
self.addEventListener('activate', (e)=>{
  e.waitUntil(
    caches.keys().then((keys)=> Promise.all(
      keys.filter((k)=> k !== CACHE).map((k)=> caches.delete(k))
    )).then(()=> self.clients.claim())
  );
});

/* 取得: ネットワーク優先。取得できたらキャッシュも更新。
   失敗時はキャッシュ、無ければ index.html を返す（SPAフォールバック）。 */
self.addEventListener('fetch', (e)=>{
  const req = e.request;
  if(req.method !== 'GET') return;
  e.respondWith(
    fetch(req).then((res)=>{
      const copy = res.clone();
      caches.open(CACHE).then((c)=> c.put(req, copy)).catch(()=>{});
      return res;
    }).catch(()=>
      caches.match(req).then((r)=> r || caches.match('./index.html'))
    )
  );
});
