import { CommonModule } from '@angular/common';
import { Component, OnDestroy, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { IonIcon } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { refreshOutline, expandOutline, contractOutline } from 'ionicons/icons';

interface AuditEvent {
  timestamp: string; source: string; stage: string; status: number; outcome: string;
  code: string; durationMs: number; invocationId: string;
}
interface RequestHistory {
  correlationId: string; timestamp: string; user: string; userId: string; operation: string; method: string;
  status: number | null; outcome: string; durationMs: number | null; exchangeOutcome: string;
  incomplete: boolean; events: AuditEvent[];
}
interface History {
  requests: RequestHistory[]; kql: string; generatedAt: string;
  stats: { requests: number; success: number; failure: number; pending: number; exchangeSuccess: number; exchangeFailure: number; averageDurationMs: number | null };
}
@Component({
  selector: 'app-exchange-history', standalone: true, imports: [CommonModule, FormsModule, IonIcon],
  templateUrl: './history.page.html', styleUrls: ['./stats.page.scss', './history.page.scss'],
})
export class HistoryPage implements OnDestroy {
  readonly data = signal<History | null>(null);
  readonly loading = signal(false);
  readonly error = signal('');
  readonly authStatus = signal(0);
  readonly expanded = signal(new Set<string>());
  readonly today = new Date().toISOString().slice(0, 10);
  readonly oldest = new Date(Date.now() - 89 * 86400000).toISOString().slice(0, 10);
  start = new Date(Date.now() - 29 * 86400000).toISOString().slice(0, 10);
  end = this.today;
  outcome = 'all';
  user = '';
  private pending?: AbortController;
  constructor() { addIcons({ refreshOutline, expandOutline, contractOutline }); void this.load(); }
  ngOnDestroy(): void { this.pending?.abort(); }
  async load(): Promise<void> {
    this.pending?.abort();
    const pending = new AbortController();
    this.pending = pending;
    this.loading.set(true); this.error.set(''); this.authStatus.set(0); this.data.set(null);
    try {
      const query = new URLSearchParams({ start: this.start, end: this.end, outcome: this.outcome, user: this.user });
      const response = await fetch(`/api/exchanges/history?${query}`, { credentials: 'same-origin', cache: 'no-store', signal: pending.signal });
      if ([401, 403].includes(response.status)) { this.authStatus.set(response.status); return; }
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to load request history.');
      if (!Array.isArray(data.requests) || !data.stats || typeof data.kql !== 'string') throw new Error('Invalid history response.');
      this.data.set(data); this.expanded.set(new Set());
    } catch (error) { if (!pending.signal.aborted) this.error.set(error instanceof Error ? error.message : 'Unable to load request history.'); }
    finally { if (this.pending === pending) this.loading.set(false); }
  }
  expandAll(open: boolean): void { this.expanded.set(new Set(open ? this.data()?.requests.map(request => request.correlationId) : [])); }
  toggle(id: string, event: Event): void {
    const next = new Set(this.expanded());
    if ((event.target as HTMLDetailsElement).open) next.add(id); else next.delete(id);
    this.expanded.set(next);
  }
}