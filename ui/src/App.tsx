/* LXR-STORAGE — the keeper's book | © 2026 iBoss21 / LXRCore
   open { payload: { yard, units[], sizes[], cash, maxDays, graceDays, maxKeys } } · close
   callbacks: rent { no, days } · manage { no, what, arg } · close */
import { useEffect, useMemo, useState } from 'react';
import { onMessage, applyChrome, makeT, post, money, pad, type Msg } from './nui';

type Unit = { no: number; size: string; state: 'free' | 'paid' | 'locked' | 'cleared'; mine: boolean; key: boolean; daysLeft?: number; code?: boolean; keys?: string[]; tenant?: string };
type Size = { id: string; slots: number; weight: number; rent: number };
type Book = { yard: { id: string; label: string }; units: Unit[]; sizes: Size[]; cash: number; maxDays: number; graceDays: number; maxKeys: number };

export function App() {
  const [B, setB] = useState<Book | null>(null);
  const [L, setL] = useState<Record<string, string>>({});
  const [pick, setPick] = useState<number | null>(null);
  const [days, setDays] = useState(7);
  const [code, setCode] = useState('');
  const [view, setView] = useState<'all' | 'mine'>('all');
  const [sure, setSure] = useState(false);
  const [busy, setBusy] = useState(false);
  const t = makeT(L);

  useEffect(() => onMessage((m: Msg) => {
    applyChrome(m);
    if (m.locale) setL(m.locale);
    if (m.action === 'open') { setB(m.payload); setPick(null); setDays(7); setCode(''); setSure(false); setView(m.payload && m.payload.units.some((u: Unit) => u.mine || u.key) ? 'mine' : 'all'); }
    if (m.action === 'close') setB(null);
  }), []);
  useEffect(() => { const k = (e: KeyboardEvent) => { if (e.key === 'Escape' || (e.key === 'Backspace' && (e.target as HTMLElement).tagName !== 'INPUT')) post('close'); }; document.addEventListener('keydown', k); return () => document.removeEventListener('keydown', k); }, []);

  const sizeOf = (id: string) => B?.sizes.find((s) => s.id === id);
  const unit = useMemo(() => B && pick != null ? B.units.find((u) => u.no === pick) || null : null, [B, pick]);
  const shown = useMemo(() => B ? B.units.filter((u) => view === 'all' || u.mine || u.key) : [], [B, view]);
  const price = (u: Unit, d: number) => { const s = sizeOf(u.size); return s ? Math.round(s.rent * d * 100) / 100 : 0; };
  const call = async (name: string, body: any) => { if (busy) return; setBusy(true); const r = await post<{ ok: boolean; data?: Book }>(name, body); setBusy(false); if (r.ok && r.data) { setB(r.data); setSure(false); } };

  if (!B) return null;
  const stateLabel = (u: Unit) => u.mine ? t('ui.paid') : u.key ? t('ui.key') : u.state === 'free' ? t('ui.free') : u.state === 'cleared' ? t('ui.cleared') : t('ui.taken');
  const bigger = unit && unit.mine ? B.sizes.filter((s) => s.rent > (sizeOf(unit.size)?.rent || 0)) : [];

  return (
    <div id="app">
      <header className="st-top lxr-hit">
        <div className="st-brand"><img className="st-logo" src="img/lxrcore-logo.png" alt="" /><div><span className="lxr-mono lxr-t-ash">{t('ui.kicker')}</span><h1 className="lxr-cut st-title">{B.yard.label}</h1></div></div>
        <span className="lxr-grow" />
        <div className="st-cash lxr-chip"><span className="lxr-mono lxr-t-smoke">{t('ui.cash')}</span><span className="lxr-num">{money(B.cash)}</span></div>
        <span className="st-hint lxr-mono lxr-t-smoke"><span className="lxr-key">Esc</span> {t('ui.hint_close')}</span>
      </header>

      <section className="st-yard lxr-hit">
        <div className="st-yard__head lxr-rule-b">
          <button className={'st-tab' + (view === 'mine' ? ' is-on' : '')} onClick={() => setView('mine')}>{t('ui.your_units')}</button>
          <button className={'st-tab' + (view === 'all' ? ' is-on' : '')} onClick={() => setView('all')}>{t('ui.all_units')}</button>
          <span className="lxr-grow" />
          <div className="st-legend lxr-mono lxr-t-smoke">{B.sizes.map((s) => <span key={s.id}>{t('ui.size_' + s.id)} · {s.slots} {t('ui.slots')} · {money(s.rent)} {t('ui.per_day')}</span>)}</div>
        </div>
        <div className="st-grid">
          {shown.length === 0 && <div className="st-empty lxr-t-smoke">{t('ui.all_units')}: 0</div>}
          {shown.map((u) => (
            <button key={u.no} className={'st-unit st-unit--' + u.size + (u.mine ? ' is-mine' : '') + (u.key ? ' is-key' : '') + (u.state !== 'free' && !u.mine && !u.key ? ' is-taken' : '') + (pick === u.no ? ' is-on' : '')} onClick={() => { setPick(u.no); setSure(false); setDays(7); }}>
              <span className="st-unit__no lxr-mono">{pad(u.no)}</span>
              <span className="st-unit__size lxr-cut">{t('ui.size_' + u.size)}</span>
              <span className="st-unit__state lxr-mono">{stateLabel(u)}{u.mine && u.daysLeft != null ? ' · ' + t('ui.days_left', { n: Math.ceil(u.daysLeft) }) : ''}</span>
              {u.mine && u.daysLeft != null && <span className="lxr-meter st-unit__meter"><span className={'lxr-meter-fill' + (u.daysLeft < 2 ? ' is-bad' : u.daysLeft < 5 ? ' is-warn' : '')} style={{ width: Math.min(100, (u.daysLeft / B.maxDays) * 100) + '%' }} /></span>}
            </button>
          ))}
        </div>
        <div className="st-foot lxr-mono lxr-t-smoke">{t('ui.grace', { n: B.graceDays })}</div>
      </section>

      <aside className={'st-side lxr-hit' + (unit ? '' : ' is-empty')}>
        {!unit && <div className="st-empty lxr-t-smoke">{t('ui.unit')} —</div>}
        {unit && (() => { const s = sizeOf(unit.size)!; return (
          <>
            <div className="st-side__head lxr-rule-b"><span className="lxr-mono lxr-t-ash">{t('ui.unit')} {pad(unit.no)}</span><span className="lxr-grow" /><span className="lxr-mono lxr-t-smoke">{stateLabel(unit)}</span></div>
            <div className="st-side__size lxr-cut">{t('ui.size_' + unit.size)}</div>
            <div className="st-side__meta lxr-mono lxr-t-smoke">{s.slots} {t('ui.slots')} · {Math.round(s.weight / 1000)} {t('ui.weight')} · {money(s.rent)} {t('ui.per_day')}</div>
            {unit.tenant && <div className="st-side__meta lxr-mono lxr-t-smoke">{t('ui.tenant')}: {unit.tenant}</div>}

            {(unit.state === 'free' || unit.state === 'cleared' || unit.mine) && (
              <div className="st-block">
                <div className="lxr-mono lxr-t-ash st-block__k">{unit.mine ? t('ui.extend') : t('ui.rent')}</div>
                <div className="st-days"><input className="lxr-input" type="number" min={1} max={B.maxDays} value={days} onChange={(e) => setDays(Math.max(1, Math.min(B.maxDays, Number(e.target.value) || 1)))} /><span className="lxr-mono lxr-t-smoke">{t('ui.days')}</span><span className="lxr-grow" /><span className="lxr-num">{money(price(unit, days))}</span></div>
                <button className="lxr-btn" disabled={busy || price(unit, days) > B.cash} onClick={() => call('rent', { no: unit.no, days })}>{t('ui.rent_days', { n: days })}</button>
              </div>
            )}

            {unit.mine && (
              <>
                <div className="st-block">
                  <div className="lxr-mono lxr-t-ash st-block__k">{t('ui.code')}</div>
                  <div className="st-days"><input className="lxr-input" inputMode="numeric" maxLength={6} placeholder={unit.code ? '••••' : '—'} value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))} /><button className="lxr-btn lxr-btn-sm" disabled={busy || code.length < 3} onClick={() => { call('manage', { no: unit.no, what: 'code', arg: code }); setCode(''); }}>{t('ui.set_code')}</button>{unit.code && <button className="lxr-btn lxr-btn-ghost lxr-btn-sm" disabled={busy} onClick={() => call('manage', { no: unit.no, what: 'code', arg: '' })}>{t('ui.clear_code')}</button>}</div>
                </div>
                <div className="st-block">
                  <div className="lxr-mono lxr-t-ash st-block__k">{t('ui.keys')} · {(unit.keys || []).length}/{B.maxKeys}</div>
                  {(unit.keys || []).map((k) => <div key={k} className="lxr-row st-keyrow"><span className="lxr-row-name lxr-mono">{k}</span><span className="lxr-grow" /><button className="lxr-btn lxr-btn-ghost lxr-btn-sm" disabled={busy} onClick={() => call('manage', { no: unit.no, what: 'unkey', arg: k })}>{t('ui.take_key')}</button></div>)}
                  <button className="lxr-btn lxr-btn-ghost lxr-btn-sm" disabled={busy || (unit.keys || []).length >= B.maxKeys} onClick={() => call('manage', { no: unit.no, what: 'key' })}>{t('ui.give_key')}</button>
                </div>
                {bigger.length > 0 && (
                  <div className="st-block">
                    <div className="lxr-mono lxr-t-ash st-block__k">{t('ui.manage')}</div>
                    {bigger.map((b) => <button key={b.id} className="lxr-btn lxr-btn-ghost lxr-btn-sm" disabled={busy} onClick={() => call('manage', { no: unit.no, what: 'upgrade', arg: b.id })}>{t('ui.upgrade_to', { size: t('ui.size_' + b.id) })} · {money(Math.max(1, Math.ceil(unit.daysLeft || 1)) * (b.rent - s.rent))}</button>)}
                  </div>
                )}
                <div className="st-block">
                  {!sure ? <button className="lxr-btn lxr-btn-ghost lxr-btn-sm" onClick={() => setSure(true)}>{t('ui.give_up')}</button>
                    : <><span className="lxr-mono lxr-t-ash">{t('ui.give_up_confirm')}</span><div className="st-days"><button className="lxr-btn lxr-btn-bad lxr-btn-sm" disabled={busy} onClick={() => call('manage', { no: unit.no, what: 'give_up' })}>{t('ui.give_up')}</button><button className="lxr-btn lxr-btn-ghost lxr-btn-sm" onClick={() => setSure(false)}>✕</button></div></>}
                </div>
              </>
            )}
          </>
        ); })()}
      </aside>
    </div>
  );
}
