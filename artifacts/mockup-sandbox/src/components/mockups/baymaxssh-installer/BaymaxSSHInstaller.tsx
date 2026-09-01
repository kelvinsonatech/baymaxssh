import { useMemo, useState } from "react";
import {
  Check,
  CheckCircle2,
  Clipboard,
  Command,
  Globe2,
  HardDrive,
  Info,
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

const protocolOptions = [
  { id: "ssh", name: "SSH", detail: "22", icon: Terminal, tone: "text-[#71d6a0] bg-[#163b34]" },
  { id: "websocket", name: "WebSocket", detail: "80 / 443", icon: Wifi, tone: "text-[#7ed4e5] bg-[#163642]" },
  { id: "ssl", name: "SSL / TLS", detail: "certbot", icon: LockKeyhole, tone: "text-[#f3c27f] bg-[#493a25]" },
  { id: "xray", name: "Xray", detail: "VLESS", icon: Zap, tone: "text-[#d7a7ef] bg-[#382947]" },
  { id: "slowdns", name: "SlowDNS", detail: "NS tunnel", icon: Globe2, tone: "text-[#9dc4ef] bg-[#233a55]" },
  { id: "udp", name: "UDP tunnel", detail: "optional", icon: Radio, tone: "text-[#f59d82] bg-[#492d2b]" },
];

const installCommand = "bash <(curl -fsSL https://raw.githubusercontent.com/kelvinsonatech/baymaxssh/main/ssh-ssl-setup.sh)";

export function BaymaxSSHInstaller() {
  const [domain, setDomain] = useState("edge.kairo-lab.net");
  const [selected, setSelected] = useState<Record<string, boolean>>({
    ssh: true,
    websocket: true,
    ssl: true,
    xray: true,
    slowdns: true,
    udp: false,
  });
  const [phase, setPhase] = useState<"idle" | "running" | "complete">("idle");
  const [copied, setCopied] = useState(false);
  const selectedCount = useMemo(() => Object.values(selected).filter(Boolean).length, [selected]);

  const toggleProtocol = (id: string) => {
    if (id === "ssh") return;
    setSelected((current) => ({ ...current, [id]: !current[id] }));
  };

  const copyCommand = async () => {
    try {
      await navigator.clipboard.writeText(installCommand);
    } catch {
      // Clipboard access is optional in the preview.
    }
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1500);
  };

  const startInstall = () => {
    if (!domain.trim() || phase === "running") return;
    setPhase("running");
    window.setTimeout(() => setPhase("complete"), 2200);
  };

  const resetInstall = () => setPhase("idle");
  const progressWidth = phase === "complete" ? "100%" : phase === "running" ? "68%" : "4%";

  return (
    <main className="min-h-[100dvh] overflow-hidden bg-[#111d20] text-[#e8eee8] selection:bg-[#f07859]/40">
      <div className="pointer-events-none fixed inset-0 opacity-30" style={{ backgroundImage: "linear-gradient(rgba(143,185,170,.04) 1px, transparent 1px), linear-gradient(90deg, rgba(143,185,170,.04) 1px, transparent 1px)", backgroundSize: "32px 32px" }} />
      <header className="relative z-10 border-b border-[#2a3a3c] bg-[#142326]/90">
        <div className="mx-auto flex max-w-[1440px] items-center justify-between px-5 py-4 sm:px-8 lg:px-12">
          <div className="flex items-center gap-3">
            <div className="relative flex h-9 w-9 items-center justify-center rounded-xl bg-[#ef7557] shadow-[0_7px_20px_rgba(239,117,87,.2)]">
              <div className="h-4 w-5 rounded-full border-2 border-[#fff3e9]" />
              <span className="absolute left-[12px] top-[13px] h-1 w-1 rounded-full bg-[#fff3e9]" />
              <span className="absolute right-[12px] top-[13px] h-1 w-1 rounded-full bg-[#fff3e9]" />
            </div>
            <div>
              <div className="font-mono text-[14px] font-bold tracking-[-.04em] text-[#f1f4eb]">baymax<span className="text-[#f08364]">ssh</span></div>
              <div className="font-mono text-[9px] uppercase tracking-[.17em] text-[#7f9690]">script installer</div>
            </div>
          </div>
          <div className="flex items-center gap-3 font-mono text-[10px] uppercase tracking-[.13em] text-[#7f9690]">
            <span className="hidden items-center gap-2 sm:flex"><span className="h-2 w-2 rounded-full bg-[#65ca91] shadow-[0_0_0_4px_rgba(101,202,145,.11)]" /> shell ready</span>
            <span className="rounded-md border border-[#334649] bg-[#1d3033] px-2.5 py-1.5 text-[#a6b6ae]">v2.4.1</span>
          </div>
        </div>
      </header>

      <section className="relative z-10 mx-auto grid max-w-[1440px] gap-6 px-5 py-6 sm:px-8 lg:grid-cols-[minmax(0,1fr)_380px] lg:gap-7 lg:px-12 lg:py-8">
        <div className="min-w-0 space-y-5">
          <div className="rounded-2xl border border-[#2d4141] bg-[#17282b] p-5 shadow-[0_20px_60px_rgba(0,0,0,.16)] sm:p-6">
            <div className="mb-5 flex flex-wrap items-start justify-between gap-3">
              <div>
                <div className="mb-2 flex items-center gap-2 font-mono text-[10px] uppercase tracking-[.17em] text-[#f08364]"><Command className="h-3.5 w-3.5" /> baymaxssh / install.sh</div>
                <h1 className="text-[clamp(1.8rem,4vw,3.5rem)] font-semibold leading-[.98] tracking-[-.06em] text-[#eef2e9]">Provision your server.</h1>
                <p className="mt-3 max-w-[590px] text-sm leading-6 text-[#9bada5]">One reviewed command for the essentials. Your existing SSH access stays in place while the script prepares each service.</p>
              </div>
              <div className="rounded-lg border border-[#38504e] bg-[#122124] px-3 py-2 font-mono text-[10px] text-[#9eb1a8]"><span className="text-[#67cd91]">●</span> local execution</div>
            </div>
            <div className="flex flex-col gap-3 rounded-xl border border-[#324b49] bg-[#0d191c] p-3 sm:flex-row sm:items-center">
              <div className="flex min-w-0 flex-1 items-center gap-2 font-mono text-[11px] leading-5 text-[#c3d3ca]">
                <span className="text-[#ed7d60]">$</span>
                <span className="truncate">{installCommand}</span>
              </div>
              <button onClick={copyCommand} className="flex shrink-0 items-center justify-center gap-2 rounded-lg border border-[#3c5552] bg-[#203538] px-3 py-2 font-mono text-[10px] uppercase tracking-[.08em] text-[#d6e5d8] transition hover:border-[#76ad98] hover:bg-[#294542]" aria-label="Copy install command">
                {copied ? <Check className="h-3.5 w-3.5 text-[#69cf94]" /> : <Clipboard className="h-3.5 w-3.5" />}
                {copied ? "copied" : "copy"}
              </button>
            </div>
          </div>

          <div className="grid gap-5 xl:grid-cols-[1fr_1.1fr]">
            <div className="rounded-2xl border border-[#2d4141] bg-[#17282b] p-5 sm:p-6">
              <div className="mb-5 flex items-center justify-between">
                <div><div className="font-mono text-[10px] uppercase tracking-[.16em] text-[#f08364]">01 / target</div><h2 className="mt-1 text-lg font-semibold tracking-[-.03em]">Connection details</h2></div>
                <Server className="h-5 w-5 text-[#709187]" />
              </div>
              <label htmlFor="domain" className="mb-2 block font-mono text-[10px] uppercase tracking-[.14em] text-[#8ba099]">Public hostname</label>
              <div className="flex items-center gap-2 rounded-xl border border-[#38504e] bg-[#0d191c] px-3.5 py-3 focus-within:border-[#ef866a]">
                <Globe2 className="h-4 w-4 shrink-0 text-[#789b90]" />
                <input id="domain" value={domain} onChange={(event) => setDomain(event.target.value)} className="w-full bg-transparent font-mono text-sm text-[#e4eee6] outline-none placeholder:text-[#637b74]" placeholder="server.example.com" />
              </div>
              <div className="mt-4 grid grid-cols-2 gap-2.5">
                <div className="rounded-lg border border-[#2d4541] bg-[#142326] p-3"><div className="flex items-center gap-1.5 font-mono text-[9px] uppercase tracking-[.12em] text-[#7e978e]"><HardDrive className="h-3 w-3" /> host</div><div className="mt-2 font-mono text-xs text-[#c6d6ce]">vps.fremont-02</div></div>
                <div className="rounded-lg border border-[#2d4541] bg-[#142326] p-3"><div className="flex items-center gap-1.5 font-mono text-[9px] uppercase tracking-[.12em] text-[#7e978e]"><ShieldCheck className="h-3 w-3" /> os</div><div className="mt-2 font-mono text-xs text-[#c6d6ce]">Ubuntu 24.04</div></div>
              </div>
              <p className="mt-4 flex items-start gap-2 text-[10px] leading-4 text-[#7e978e]"><Info className="mt-0.5 h-3.5 w-3.5 shrink-0 text-[#76a491]" /> Point DNS to this server before enabling SSL certificates.</p>
            </div>

            <div className="rounded-2xl border border-[#2d4141] bg-[#17282b] p-5 sm:p-6">
              <div className="mb-5 flex items-center justify-between">
                <div><div className="font-mono text-[10px] uppercase tracking-[.16em] text-[#f08364]">02 / modules</div><h2 className="mt-1 text-lg font-semibold tracking-[-.03em]">Choose what runs</h2></div>
                <span className="font-mono text-[10px] text-[#7e978e]">{selectedCount} / 6 enabled</span>
              </div>
              <div className="grid grid-cols-2 gap-2">
                {protocolOptions.map(({ id, name, detail, icon: Icon, tone }) => {
                  const active = selected[id];
                  return (
                    <button key={id} onClick={() => toggleProtocol(id)} disabled={id === "ssh"} aria-pressed={active} className={`flex items-center gap-2.5 rounded-xl border p-3 text-left transition ${active ? "border-[#49645e] bg-[#1e3535]" : "border-[#2b4040] bg-[#142326] opacity-65"} ${id !== "ssh" ? "hover:border-[#708d80]" : "cursor-default"}`}>
                      <span className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${tone}`}><Icon className="h-4 w-4" /></span>
                      <span className="min-w-0"><span className="block truncate text-[11px] font-semibold text-[#dbe7df]">{name}</span><span className="mt-0.5 block truncate font-mono text-[9px] text-[#81988f]">{detail}</span></span>
                      <span className={`ml-auto h-2 w-2 shrink-0 rounded-full ${active ? "bg-[#69cf94]" : "bg-[#506561]"}`} />
                    </button>
                  );
                })}
              </div>
            </div>
          </div>

          <div className="rounded-2xl border border-[#2d4141] bg-[#0d191c] shadow-[0_20px_60px_rgba(0,0,0,.14)]">
            <div className="flex items-center justify-between border-b border-[#243a3b] px-5 py-3.5 sm:px-6">
              <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-[.14em] text-[#91a69d]"><Terminal className="h-3.5 w-3.5 text-[#f08364]" /> execution log</div>
              <span className={`font-mono text-[10px] uppercase tracking-[.12em] ${phase === "complete" ? "text-[#69cf94]" : phase === "running" ? "text-[#f4c77e]" : "text-[#6f8880]"}`}>{phase === "complete" ? "complete" : phase === "running" ? "running" : "idle"}</span>
            </div>
            <div className="space-y-2 px-5 py-5 font-mono text-[11px] leading-5 sm:px-6">
              <div className="text-[#7f9890]"><span className="text-[#65ca91]">[ready]</span> preflight checks passed</div>
              <div className="text-[#7f9890]"><span className="text-[#65ca91]">[ready]</span> SSH access preserved on port 22</div>
              {phase !== "idle" && <div className="text-[#c6d5cc]"><span className="text-[#f2bd72]">[run]</span> installing {selectedCount} selected modules for {domain}</div>}
              {phase === "complete" && <div className="text-[#c6d5cc]"><span className="text-[#65ca91]">[done]</span> services enabled and credentials written to /root/baymaxssh.txt</div>}
              {phase === "idle" && <div className="text-[#5e7770]"><span className="text-[#5e7770]">[wait]</span> command is ready when you are</div>}
            </div>
          </div>
        </div>

        <aside className="space-y-5">
          <div className="relative min-h-[250px] overflow-hidden rounded-2xl border border-[#415052] bg-[#202f32] shadow-[0_20px_60px_rgba(0,0,0,.2)]">
            <img src="/__mockup/images/baymaxssh-reference.png" alt="Baymax and his armored companion, used as the BaymaxSSH visual reference" className="absolute inset-0 h-full w-full object-cover object-[57%_44%] opacity-75" />
            <div className="absolute inset-0 bg-gradient-to-t from-[#0f2023] via-[#102326]/25 to-transparent" />
            <div className="relative flex min-h-[250px] flex-col justify-between p-5">
              <div className="flex items-center justify-between"><span className="rounded-full border border-white/20 bg-[#112326]/60 px-2.5 py-1 font-mono text-[9px] uppercase tracking-[.12em] text-[#dce6dc] backdrop-blur">visual reference / 01</span><span className="flex items-center gap-1.5 font-mono text-[9px] uppercase tracking-[.12em] text-[#b7d1c2]"><span className="h-1.5 w-1.5 rounded-full bg-[#69cf94]" /> calm mode</span></div>
              <div><div className="mb-2 flex items-center gap-2 font-mono text-[10px] uppercase tracking-[.14em] text-[#f3ad91]"><ShieldCheck className="h-3.5 w-3.5" /> human-sized setup</div><p className="max-w-[280px] text-xl font-semibold leading-tight tracking-[-.04em] text-[#f3eee4]">The script does the heavy lifting.</p></div>
            </div>
          </div>

          <div className="rounded-2xl border border-[#2d4141] bg-[#17282b] p-5 sm:p-6">
            <div className="mb-5 flex items-center justify-between"><div><div className="font-mono text-[10px] uppercase tracking-[.16em] text-[#f08364]">03 / run</div><h2 className="mt-1 text-lg font-semibold tracking-[-.03em]">Execute installer</h2></div><CheckCircle2 className={`h-5 w-5 ${phase === "complete" ? "text-[#69cf94]" : "text-[#66877c]"}`} /></div>
            <div className="mb-2 flex items-center justify-between font-mono text-[10px] uppercase tracking-[.1em] text-[#7e978e]"><span>progress</span><span>{phase === "complete" ? "100%" : phase === "running" ? "68%" : "4%"}</span></div>
            <div className="mb-5 h-2 overflow-hidden rounded-full bg-[#273b3b]"><div className="h-full rounded-full bg-[#ef795b] transition-all duration-1000" style={{ width: progressWidth }} /></div>
            <button onClick={phase === "complete" ? resetInstall : startInstall} disabled={phase === "running" || !domain.trim()} className="flex w-full items-center justify-center gap-2 rounded-xl bg-[#ed7557] px-4 py-3.5 text-sm font-semibold text-[#fff6ed] shadow-[0_10px_24px_rgba(237,117,87,.18)] transition hover:bg-[#f18567] focus:outline-none focus:ring-4 focus:ring-[#ee987d]/30 disabled:cursor-default disabled:opacity-65">
              {phase === "complete" ? <><X className="h-4 w-4" /> reset console</> : phase === "running" ? <><span className="h-4 w-4 animate-pulse rounded-full border-2 border-white/40 border-t-white" /> running script</> : <><Play className="h-4 w-4 fill-current" /> run baymaxssh</>}
            </button>
            <p className="mt-4 flex items-start gap-2 text-[10px] leading-4 text-[#829991]"><ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-[#65ca91]" /> Review the command before running. The installer changes only the services selected above.</p>
          </div>
        </aside>
      </section>

      <footer className="relative z-10 mx-auto flex max-w-[1440px] items-center justify-between border-t border-[#263a3b] px-5 py-4 font-mono text-[9px] uppercase tracking-[.12em] text-[#6f8880] sm:px-8 lg:px-12">
        <span>baymaxssh / script ui</span>
        <span className="hidden items-center gap-2 sm:flex"><span className="h-1.5 w-1.5 rounded-full bg-[#65ca91]" /> no credentials stored in this console</span>
      </footer>
    </main>
  );
}