import { HttpClient } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, switchMap, takeWhile, timer } from 'rxjs';

import { environment } from '../../environments/environment';

export interface ConversationStarter {
  title: string;
  text: string;
}

export interface AgentSummary {
  id: string;
  foundryAgentName: string;
  displayName: string;
  shortName: string;
  tagline: string;
  description: string;
  accentColor: string;
  tools: string[];
  conversationStarters: ConversationStarter[];
  iconUrl: string;
  m365PackageUrl: string;
}

export interface GeneratedFile {
  fileId: string;
  containerId: string;
  filename: string;
  downloadUrl: string;
  previewUrl?: string;
  mediaType?: string;
}

export interface ChatResult {
  agentId: string;
  conversationId: string;
  reply: string;
  toolCalls: string[];
  files: GeneratedFile[];
}

export interface ChatJobAccepted {
  jobId: string;
  agentId: string;
  status: string;
  pollUrl: string;
}

export interface ChatJobStatus {
  jobId: string;
  agentId: string;
  status: 'running' | 'completed' | 'failed';
  result?: ChatResult;
  error?: string;
}

export interface M365Package {
  agentId: string;
  displayName: string;
  teamsAppId: string;
  fileName: string;
  downloadUrl: string;
  contents: string[];
  requiresApiKeyReferenceId: boolean;
}

const POLL_INTERVAL_MS = 3000;

@Injectable({ providedIn: 'root' })
export class ApiService {
  private readonly http = inject(HttpClient);
  readonly baseUrl = environment.apiBaseUrl.replace(/\/$/, '');

  listAgents(): Observable<AgentSummary[]> {
    return this.http.get<AgentSummary[]>(`${this.baseUrl}/api/agents`);
  }

  listPackages(): Observable<M365Package[]> {
    return this.http.get<M365Package[]>(`${this.baseUrl}/api/m365/packages`);
  }

  /** Starts a turn and emits every poll until the job completes or fails. */
  chat(agentId: string, message: string, conversationId?: string): Observable<ChatJobStatus> {
    return this.http
      .post<ChatJobAccepted>(`${this.baseUrl}/api/agents/${agentId}/chat`, {
        message,
        conversationId: conversationId ?? null,
      })
      .pipe(
        switchMap((job) =>
          timer(0, POLL_INTERVAL_MS).pipe(
            switchMap(() =>
              this.http.get<ChatJobStatus>(`${this.baseUrl}/api/chat/jobs/${job.jobId}`),
            ),
            takeWhile((status) => status.status === 'running', true),
          ),
        ),
      );
  }

  packageDownloadUrl(agentId: string, apiKeyReferenceId?: string): string {
    const url = `${this.baseUrl}/api/m365/packages/${agentId}`;
    const reference = apiKeyReferenceId?.trim();
    return reference ? `${url}?apiKeyReferenceId=${encodeURIComponent(reference)}` : url;
  }

  swaggerUrl(): string {
    return `${this.baseUrl}/docs`;
  }
}
