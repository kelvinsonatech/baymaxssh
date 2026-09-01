import { useState } from "react";
import {
  ArrowRight,
  Check,
  CheckCircle2,
  ChevronDown,
  CircleHelp,
  Copy,
  Globe2,
  HardDrive,
  LockKeyhole,
  Play,
  Radio,
  Server,
  ShieldCheck,
  Terminal,
  Wifi,
  X,
  Zap,
} from "lucide-react";

const protocols = [
  { name: "SSH", detail: "Port 22", icon: Terminal, color: "bg-[#e8f2ec] text-[#28704f]" },
  { name: "WebSocket", detail: "Port 80 / 443", icon: Wifi, color: "bg-[#e9eef8] text-[#3d5d9c]" },
  { name: "SSL / TLS", detail: "Let's Encrypt", icon: LockKeyhole, color: "bg-[#f8efdf] text-[#9a6d28]" },
  { name: "Xray", detail: "VLESS + Reality", icon: Zap, color: "bg-[#f1e9f2] text-[#81518a]" },
  { name: "SlowDNS", detail: "NS tunneling", icon: Globe2, color: "bg-[#e7f0f1] text-[#37777d]" },
  { name: "UDP tunnel", detail: "Optional", icon: Radio, color: "bg-[#f5e9e4] text-[#a65d49]" },
];

export function BaymaxSSHInstaller() {
  const [domain, setDomain] = useState("edge.kairo-lab.net");
  const [udp, setUdp] = useState(true);
  const [installing, setInstalling] = useState(false);
  const [installed, setInstalled] = useState(false);
  const [copied, setCopied] = useState(false);

  const startInstall = () => {
    setInstalling(true);
    window.setTimeout(() => {
      setInstalling(false);
      setInstalled(true);
    }, 1800);
  };

  const copyDomain = async () => {
    try {
      await navigator.clipboard.writeText(domain);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1400);
    } catch {
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1400);
    }
  };

  return (
    <main className="min-h-[100dvh] overflow-hidden bg-[#f5f2ec] text-[#17252a] selection:bg-[#f39a78]/30">
      <div className="pointer-events-none fixed inset-0 opacity-[0.16]" style={{ backgroundImage: "radial-gradient(#70817c 0.65px, transparent 0.65px)", backgroundSize: "15px 15px" }} />
      <header className="relative z-10 mx-auto flex w-full max-w-[1380px] items-center justify-between px-5 py-5 sm:px-8 lg:px-12">
        <div className="flex items-center gap-3">
          <div className="relative flex h-10 w-10 items-center justify-center rounded-[13px] bg-[#f26b4e] shadow-[0_5px_16px_rgba(193,74,46,.18)]">
            <div className="h-5 w-6 rounded-[50%] border-[2.5px] border-[#fff4ea]" />
            <span className="absolute left-[13px] top-[14px] h-1 w-1 rounded-full bg-[#fff4ea]" />
            <span className="absolute right-[13px] top-[14px] h-1 w-1 rounded-full bg-[#fff4ea]" />
          </div>
          <div>
            <div className="font-mono text-[15px] font-bold tracking-[-.04em] text-[#1d3033]">baymax<span className="text-[#ed7355]">ssh</span></div>
            <div className="text-[9px] font-semibold uppercase tracking-[.2em] text-[#788582]">friendly server setup</div>
          </div>
        </div>
        <div className="hidden items-center gap-5 text-[11px] font-semibold uppercase tracking-[.16em] text-[#71807e] sm:flex">
          <span className="flex items-center gap-2"><span className="h-2 w-2 rounded-full bg-[#51a777] shadow-[0_0_0_4px_#dcecdf]" />system ready</span>
          <span className="rounded-full border border-[#d5d8d0] bg-[#f9f7f2] px-3 py-1.5 font-mono tracking-normal text-[#66726f]">v2.4.1</span>
        </div>
      </header>

      <section className="relative z-10 mx-auto grid w-full max-w-[1380px] gap-8 px-5 pb-10 pt-4 sm:px-8 lg:grid-cols-[minmax(0,1fr)_420px] lg:gap-14 lg:px-12 lg:pb-16 lg:pt-10">
        <div className="min-w-0">
          <div className="mb-8 max-w-[650px]">
            <div className="mb-4 flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.22em] text-[#d2684c]"><span className="h-px w-7 bg-[#e78b70]" /> guided installation / 01</div>
            <h1 className="font-sans text-[clamp(2.5rem,6vw,5.25rem)] font-extrabold leading-[.94] tracking-[-.07em] text-[#183034]">
              A safer way<br /><span className="text-[#df7256]">into your server.</span>
            </h1>
            <p className="mt-6 max-w-[530px] text-[15px] leading-7 text-[#64726f] sm:text-[17px]">BaymaxSSH prepares the quiet essentials first — then gives you one clear door into your VPS.</p>
          </div>

          <div className="group relative h-[260px] overflow-hidden rounded-[25px] border border-[#d1d7cf] bg-[#1d2c31] shadow-[0_18px_50px_rgba(38,55,55,.13)] sm:h-[355px] lg:h-[390px]">
            <img src="/__mockup/images/baymaxssh-reference.jpg" alt="Baymax and his armored companion, representing a friendly but capable server setup" className="h-full w-full object-cover object-[54%_48%] opacity-[.92] transition duration-700 group-hover:scale-[1.025] sm:object-[52%_46%]" />
            <div className="absolute inset-0 bg-gradient-to-r from-[#13282e]/85 via-[#13282e]/15 to-transparent" />
            <div className="absolute bottom-6 left-6 max-w-[260px] text-[#fff5e9] sm:bottom-8 sm:left-8">
              <div className="mb-2 flex items-center gap-2 text-[10px] font-bold uppercase tracking-[.22em] text-[#f8b29a]"><ShieldCheck className="h-3.5 w-3.5" /> built for calm</div>
              <p className="text-[20px] font-semibold leading-tight tracking-[-.03em]">Complex infrastructure.<br />Human-sized instructions.</p>
            </div>
            <div className="absolute right-5 top-5 rounded-full border border-white/25 bg-[#11262a]/45 px-3 py-1.5 font-mono text-[10px] text-[#e9d9ca] backdrop-blur-md">visual reference // 01</div>
          </div>

          <div className="mt-8">
            <div className="mb-4 flex items-baseline justify-between">
              <div><h2 className="text-[18px] font-bold tracking-[-.03em]">What gets installed</h2><p className="mt-1 text-xs text-[#788581]">A focused toolkit, nothing extra.</p></div>
              <span className="font-mono text-[11px] text-[#8b9691]">06 modules</span>
            </div>
            <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3">
              {protocols.map(({ name, detail, icon: Icon, color }) => (
                <div key={name} className="flex items-center gap-3 rounded-[15px] border border-[#dce0d8] bg-[#faf8f3]/75 p-3 transition hover:-translate-y-0.5 hover:border-[#c3cbc2] hover:bg-[#fffdf9]">
                  <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${color}`}><Icon className="h-[17px] w-[17px]" strokeWidth={1.8} /></div>
                  <div className="min-w-0"><div className="truncate text-[12px] font-bold">{name}</div><div className="mt-0.5 truncate font-mono text-[9px] text-[#88928d]">{detail}</div></div>
                </div>
              ))}
            </div>
          </div>
        </div>

        <aside className="relative">
          <div className="sticky top-5 rounded-[25px] border border-[#d3d9d1] bg-[#fbf9f4] p-5 shadow-[0_18px_45px_rgba(48,66,61,.08)] sm:p-7">
            <div className="mb-7 flex items-start justify-between">
              <div><div className="mb-1 font-mono text-[10px] font-bold uppercase tracking-[.17em] text-[#d2684c]">setup checklist</div><h2 className="text-[22px] font-bold tracking-[-.05em]">Ready when you are.</h2></div>
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#e0f0e3] text-[#3a8a60]"><CheckCircle2 className="h-5 w-5" /></div>
            </div>

            <div className="space-y-3">
              <div className="rounded-[15px] border border-[#dfe3db] bg-[#f5f5ef] p-4">
                <div className="mb-2 flex items-center justify-between"><label htmlFor="server" className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.12em] text-[#788581]"><Server className="h-3.5 w-3.5" /> target server</label><span className="flex items-center gap-1 text-[10px] font-semibold text-[#3d9566]"><Check className="h-3 w-3" /> connected</span></div>
                <div id="server" className="flex items-center justify-between font-mono text-[13px] text-[#26383b]"><span>vps.fremont-02</span><span className="text-[10px] text-[#909b95]">Ubuntu 24.04</span></div>
              </div>
              <div className="rounded-[15px] border border-[#dfe3db] bg-[#f5f5ef] p-4">
                <div className="mb-2 flex items-center justify-between"><label htmlFor="domain" className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.12em] text-[#788581]"><Globe2 className="h-3.5 w-3.5" /> domain</label><button onClick={copyDomain} className="flex items-center gap-1 text-[10px] font-semibold text-[#cf6b50] hover:text-[#a94d36]" aria-label="Copy domain">{copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}{copied ? "copied" : "copy"}</button></div>
                <input id="domain" value={domain} onChange={(e) => setDomain(e.target.value)} className="w-full bg-transparent font-mono text-[13px] text-[#26383b] outline-none placeholder:text-[#aeb5af] focus:ring-0" aria-label="Domain name" />
              </div>
              <button onClick={() => setUdp(!udp)} className="flex w-full items-center justify-between rounded-[15px] border border-[#dfe3db] bg-[#f5f5ef] p-4 text-left transition hover:border-[#c7d1c8]" aria-pressed={udp}>
                <span className="flex items-center gap-2.5"><span className={`flex h-7 w-7 items-center justify-center rounded-lg ${udp ? "bg-[#f5e9e4] text-[#aa604a]" : "bg-[#e4e6e0] text-[#8c9791]"}`}><Radio className="h-3.5 w-3.5" /></span><span><span className="block text-[12px] font-bold">UDP tunneling</span><span className="mt-0.5 block text-[10px] text-[#89938e]">Optional transport layer</span></span></span>
                <span className={`relative h-5 w-9 rounded-full transition ${udp ? "bg-[#db8063]" : "bg-[#c4cbc3]"}`}><span className={`absolute top-1 h-3 w-3 rounded-full bg-[#fffaf3] shadow-sm transition ${udp ? "left-5" : "left-1"}`} /></span>
              </button>
            </div>

            <div className="my-6 border-t border-dashed border-[#d7ddd5]" />
            <div className="mb-4 flex items-center justify-between text-[11px]"><span className="font-semibold text-[#6c7975]">installation status</span><span className={`font-mono ${installed ? "text-[#3e9162]" : "text-[#d1785d]"}`}>{installed ? "complete" : installing ? "working…" : "awaiting start"}</span></div>
            <div className="mb-6 h-2 overflow-hidden rounded-full bg-[#e7e9e2]"><div className={`h-full rounded-full bg-[#e58265] transition-all duration-1000 ${installed ? "w-full" : installing ? "w-[62%]" : "w-[8%]"}`} /></div>
            <button onClick={startInstall} disabled={installing || installed || !domain.trim()} className="group flex w-full items-center justify-center gap-2 rounded-[14px] bg-[#e87355] px-5 py-4 text-[13px] font-bold text-[#fff9f0] shadow-[0_9px_20px_rgba(207,99,73,.2)] transition hover:-translate-y-0.5 hover:bg-[#d96347] focus:outline-none focus:ring-4 focus:ring-[#edaa94]/50 disabled:cursor-default disabled:opacity-70 disabled:hover:translate-y-0">
              {installed ? <><Check className="h-4 w-4" /> BaymaxSSH is ready</> : installing ? <><span className="h-4 w-4 animate-pulse rounded-full border-2 border-white/40 border-t-white" /> preparing your server…</> : <><Play className="h-4 w-4 fill-current" /> begin installation <ArrowRight className="h-4 w-4 transition group-hover:translate-x-0.5" /></>}
            </button>
            <p className="mt-4 flex items-start gap-2 text-[10px] leading-4 text-[#8c9690]"><ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-[#5c9a78]" /> Your existing SSH access stays untouched. You can review every step before anything changes.</p>
          </div>
          <div className="mt-5 flex items-center justify-center gap-2 text-[10px] text-[#929b95]"><HardDrive className="h-3.5 w-3.5" /> runs locally on your VPS <span className="text-[#c2c8c1]">·</span> no credentials stored</div>
        </aside>
      </section>
      <footer className="relative z-10 mx-auto flex max-w-[1380px] items-center justify-between border-t border-[#d9ddd5] px-5 py-5 text-[10px] text-[#929b95] sm:px-8 lg:px-12">
        <span className="font-mono">BAYMAXSSH / OPERATIONS CONSOLE</span><span className="hidden items-center gap-1.5 sm:flex"><CircleHelp className="h-3.5 w-3.5" /> Need a hand? Read the setup guide <ChevronDown className="h-3 w-3 -rotate-90" /></span>
      </footer>
    </main>
  );
}