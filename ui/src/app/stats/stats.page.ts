import { CommonModule } from '@angular/common';
import { Component, OnDestroy, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { IonIcon } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { downloadOutline, refreshOutline, lockClosedOutline, arrowBackOutline } from 'ionicons/icons';

interface PeriodStats { period: string; visits: number; uniqueIps: number; }
interface LocationStats { country: string; state: string; city: string; visits: number; uniqueIps: number; }
interface Visit { timestamp: string; ip: string | null; country: string; state: string; city: string; path: string; }
interface Stats {
  totalVisits: number; uniqueIps: number; unknownIpVisits: number;
  periods: PeriodStats[]; locations: LocationStats[]; recentVisits: Visit[];
  retentionDays: number; timeZone: string; generatedAt: string;
}

@Component({
  selector: 'app-stats', standalone: true,
  imports: [CommonModule, FormsModule, IonIcon],
  templateUrl: './stats.page.html', styleUrl: './stats.page.scss',
})
export class StatsPage implements OnDestroy {
  readonly stats = signal<Stats | null>(null);
  readonly loading = signal(false);
  readonly error = signal('');
  readonly authRequired = signal(false);
  readonly forbidden = signal(false);
  readonly today = new Date().toISOString().slice(0, 10);
  readonly oldest = new Date(Date.now() - 89 * 86400000).toISOString().slice(0, 10);
  start = new Date(Date.now() - 29 * 86400000).toISOString().slice(0, 10);
  end = this.today;
  period = 'day';
  locationSearch = '';
  private pending?: AbortController;

  constructor() {
    addIcons({ downloadOutline, refreshOutline, lockClosedOutline, arrowBackOutline });
    void this.load();
  }

  ngOnDestroy(): void { this.pending?.abort(); }

  async load(): Promise<void> {
    this.pending?.abort();
    const pending = new AbortController();
    this.pending = pending;
    this.loading.set(true);
    this.error.set('');
    this.authRequired.set(false);
    this.forbidden.set(false);
    this.stats.set(null);
    try {
      const query = new URLSearchParams({ start: this.start, end: this.end, period: this.period });
      const response = await fetch(`/api/visits/stats?${query}`, { signal: pending.signal, credentials: 'same-origin', cache: 'no-store' });
      if (response.status === 401) { this.authRequired.set(true); return; }
      if (response.status === 403) { this.forbidden.set(true); return; }
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Unable to load visitor statistics.');
      if (!Array.isArray(data.periods) || !Array.isArray(data.locations)) throw new Error('The analytics endpoint is unavailable.');
      this.stats.set(data);
    } catch (error) {
      if (!pending.signal.aborted) this.error.set(error instanceof Error ? error.message : 'Unable to load visitor statistics.');
    } finally {
      if (this.pending === pending) this.loading.set(false);
    }
  }

  setRange(days: number): void {
    this.end = this.today;
    this.start = new Date(Date.now() - (days - 1) * 86400000).toISOString().slice(0, 10);
    void this.load();
  }

  locations(): LocationStats[] {
    const query = this.locationSearch.trim().toLowerCase();
    return (this.stats()?.locations ?? []).filter(row => `${row.country} ${row.state} ${row.city}`.toLowerCase().includes(query));
  }

  barWidth(visits: number): number {
    return 100 * visits / Math.max(1, ...(this.stats()?.periods.map(row => row.visits) ?? []));
  }

  exportLocations(): void {
    const cell = (value: unknown) => `"${String(value).replace(/^[=+@-]/, "'$&").replace(/"/g, '""')}"`;
    const rows = [['Country', 'State', 'City', 'Visits', 'Unique IPs'],
      ...this.locations().map(row => [row.country, row.state, row.city, row.visits, row.uniqueIps])];
    const url = URL.createObjectURL(new Blob([rows.map(row => row.map(cell).join(',')).join('\r\n')], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `showcase-locations-${this.start}-${this.end}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }
}