/* NK Automoción · configuración compartida del sistema de seguimiento.
   La clave "anon" de Supabase es pública por diseño: solo permite lo que dejan las políticas RLS.
   NUNCA pongas aquí la clave service_role. */
window.NK = (function () {
  const SB_URL = 'https://blrqwjthifbyctdydmze.supabase.co';
  const SB_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJscnF3anRoaWZieWN0ZHlkbXplIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIwNzMyODksImV4cCI6MjEwNzY0OTI4OX0.zuewhrZfLxi1CPbCLcqbqae9avch4THNzf8vwFeWSsg';
  const PHOTO_BUCKET = 'vehicle-photos';
  const WA_BUSINESS = '34614133829';
  const PHONE = '+34922293649';

  const P = 'fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" viewBox="0 0 24 24"';
  const ICONS = {
    clipboard: `<svg ${P}><rect x="6" y="4" width="12" height="17" rx="2"/><path d="M9 4V3h6v1M9 10h6M9 14h6M9 18h3"/></svg>`,
    search: `<svg ${P}><circle cx="11" cy="11" r="6.5"/><path d="m20 20-4-4"/></svg>`,
    play: `<svg ${P}><circle cx="12" cy="12" r="9"/><path d="m10 8.5 5 3.5-5 3.5z"/></svg>`,
    wrench: `<svg ${P}><path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.4-.6-.6-2.4z"/></svg>`,
    flag: `<svg ${P}><path d="M5 21V4M5 4h11l-2 4 2 4H5"/></svg>`,
    check: `<svg ${P}><circle cx="12" cy="12" r="9"/><path d="m8 12.5 3 3 5-6"/></svg>`,
    done: `<svg ${P}><path d="M3 12.5 8 17.5 21 5.5"/><path d="M3 18h18"/></svg>`,
    pause: `<svg ${P}><circle cx="12" cy="12" r="9"/><path d="M10 9v6M14 9v6"/></svg>`,
    alert: `<svg ${P}><path d="M12 3 2 20h20z"/><path d="M12 10v4M12 17h.01"/></svg>`,
    dot: `<svg ${P}><circle cx="12" cy="12" r="4"/></svg>`
  };
  const icon = k => ICONS[k] || ICONS.dot;

  const normPlate = s => String(s || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const tz = 'Atlantic/Canary';
  const fDate = d => d ? new Date(String(d).length === 10 ? d + 'T12:00:00' : d).toLocaleDateString('es-ES', { day: '2-digit', month: 'long', year: 'numeric', timeZone: tz }) : '—';
  const fShort = d => d ? new Date(String(d).length === 10 ? d + 'T12:00:00' : d).toLocaleDateString('es-ES', { day: '2-digit', month: '2-digit', year: 'numeric', timeZone: tz }) : '—';
  const fDateTime = d => d ? new Date(d).toLocaleString('es-ES', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit', timeZone: tz }) : '—';
  const fTime = d => new Date(d).toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit', second: '2-digit', timeZone: tz });
  function fRel(d) {
    const s = Math.round((Date.now() - new Date(d).getTime()) / 1000);
    if (s < 60) return 'hace unos segundos';
    const m = Math.round(s / 60); if (m < 60) return `hace ${m} min`;
    const h = Math.round(m / 60); if (h < 24) return `hace ${h} h`;
    const dd = Math.round(h / 24); return dd === 1 ? 'ayer' : `hace ${dd} días`;
  }
  const photoUrl = p => p ? `${SB_URL}/storage/v1/object/public/${PHOTO_BUCKET}/${p.split('/').map(encodeURIComponent).join('/')}` : '';
  const baseUrl = () => location.origin + location.pathname.replace(/[^/]*$/, '');
  const trackingLink = token => `${baseUrl()}seguimiento.html#t=${token}`;
  function waPhone(p) {
    let d = String(p || '').replace(/\D/g, '');
    if (d.startsWith('00')) d = d.slice(2);
    if (d.length === 9) d = '34' + d;
    return d;
  }
  function client(opts) {
    if (!window.supabase || !window.supabase.createClient) throw new Error('No se pudo cargar la librería de Supabase');
    return window.supabase.createClient(SB_URL, SB_KEY, opts || {});
  }
  return { SB_URL, SB_KEY, PHOTO_BUCKET, WA_BUSINESS, PHONE, ICONS, icon, normPlate, esc, fDate, fShort, fDateTime, fTime, fRel, photoUrl, trackingLink, waPhone, client };
})();
