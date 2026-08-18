import { CommonModule } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { IonButton, IonChip, IonIcon, IonInput, IonItem, IonLabel } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { cloudDownloadOutline, documentTextOutline, keyOutline } from 'ionicons/icons';
import { forkJoin } from 'rxjs';

import { AgentSummary, ApiService, M365Package } from '../core/api.service';

interface PackageCard extends M365Package {
  iconUrl: string;
  tagline: string;
  description: string;
  apiKeyReferenceId: string;
}

@Component({
  selector: 'app-packages',
  templateUrl: './packages.page.html',
  styleUrls: ['./packages.page.scss'],
  imports: [CommonModule, FormsModule, IonButton, IonIcon, IonChip, IonItem, IonLabel, IonInput],
})
export class PackagesPage implements OnInit {
  private readonly api = inject(ApiService);

  cards: PackageCard[] = [];
  loadError = '';

  constructor() {
    addIcons({ cloudDownloadOutline, documentTextOutline, keyOutline });
  }

  ngOnInit(): void {
    forkJoin({ agents: this.api.listAgents(), packages: this.api.listPackages() }).subscribe({
      next: ({ agents, packages }) => {
        const byId = new Map<string, AgentSummary>(agents.map((agent) => [agent.id, agent]));
        this.cards = packages.map((pkg) => ({
          ...pkg,
          iconUrl: byId.get(pkg.agentId)?.iconUrl ?? '',
          tagline: byId.get(pkg.agentId)?.tagline ?? '',
          description: byId.get(pkg.agentId)?.description ?? '',
          apiKeyReferenceId: '',
        }));
      },
      error: (error) => {
        this.loadError = `Could not load packages from ${this.api.baseUrl}. ${error?.message ?? ''}`;
      },
    });
  }

  downloadUrl(card: PackageCard): string {
    return this.api.packageDownloadUrl(card.agentId, card.apiKeyReferenceId);
  }

  openApiSpecUrl(card: PackageCard): string {
    return `${this.api.baseUrl}/api/m365/packages/${card.agentId}/openapi`;
  }
}
