import { CommonModule } from '@angular/common';
import { Component, ElementRef, OnInit, ViewChild, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  IonButton,
  IonChip,
  IonIcon,
  IonLabel,
  IonSegment,
  IonSegmentButton,
  IonSpinner,
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { addOutline, cloudDownloadOutline, sendOutline, sparklesOutline } from 'ionicons/icons';
import { QuillEditorComponent } from 'ngx-quill';

import { AgentSummary, ApiService, GeneratedFile } from '../core/api.service';
import { htmlToMarkdown, renderMarkdown } from '../core/markdown';

interface ChatMessage {
  role: 'user' | 'agent';
  html: string;
  toolCalls?: string[];
  files?: GeneratedFile[];
}

@Component({
  selector: 'app-chat',
  templateUrl: './chat.page.html',
  styleUrls: ['./chat.page.scss'],
  imports: [
    CommonModule,
    FormsModule,
    QuillEditorComponent,
    IonSegment,
    IonSegmentButton,
    IonLabel,
    IonButton,
    IonIcon,
    IonSpinner,
    IonChip,
  ],
})
export class ChatPage implements OnInit {
  private readonly api = inject(ApiService);
  @ViewChild('transcript') transcript?: ElementRef<HTMLDivElement>;

  agents: AgentSummary[] = [];
  selectedAgentId = '';
  draft = '';
  sending = false;
  loadError = '';

  /** One transcript and one Foundry conversation per agent tab. */
  private readonly transcripts: Record<string, ChatMessage[]> = {};
  private readonly conversations: Record<string, string> = {};

  readonly quillModules = {
    toolbar: [
      ['bold', 'italic', 'underline'],
      [{ list: 'ordered' }, { list: 'bullet' }],
      ['blockquote', 'code-block'],
      ['link'],
      ['clean'],
    ],
  };

  constructor() {
    addIcons({ sendOutline, addOutline, cloudDownloadOutline, sparklesOutline });
  }

  ngOnInit(): void {
    this.api.listAgents().subscribe({
      next: (agents) => {
        this.agents = agents;
        for (const agent of agents) {
          this.transcripts[agent.id] ??= [];
        }
        this.selectedAgentId = agents[0]?.id ?? '';
      },
      error: (error) => {
        this.loadError = `Could not load agents from ${this.api.baseUrl}. ${error?.message ?? ''}`;
      },
    });
  }

  get selectedAgent(): AgentSummary | undefined {
    return this.agents.find((agent) => agent.id === this.selectedAgentId);
  }

  get messages(): ChatMessage[] {
    return this.transcripts[this.selectedAgentId] ?? [];
  }

  selectAgent(agentId: string | undefined): void {
    if (agentId) {
      this.selectedAgentId = agentId;
    }
  }

  useStarter(text: string): void {
    this.draft = `<p>${text}</p>`;
  }

  newConversation(): void {
    delete this.conversations[this.selectedAgentId];
    this.transcripts[this.selectedAgentId] = [];
  }

  send(): void {
    const agent = this.selectedAgent;
    if (!agent || this.sending) {
      return;
    }
    const markdown = htmlToMarkdown(this.draft);
    if (!markdown) {
      return;
    }

    const agentId = agent.id;
    const thread = (this.transcripts[agentId] ??= []);
    thread.push({ role: 'user', html: renderMarkdown(markdown) });
    this.draft = '';
    this.sending = true;
    this.scrollToBottom();

    this.api.chat(agentId, markdown, this.conversations[agentId]).subscribe({
      next: (status) => {
        if (status.status === 'completed' && status.result) {
          this.conversations[agentId] = status.result.conversationId;
          thread.push({
            role: 'agent',
            html: renderMarkdown(
              status.result.reply || '_The agent finished without a text answer._',
            ),
            toolCalls: status.result.toolCalls,
            files: status.result.files,
          });
          this.sending = false;
          this.scrollToBottom();
        } else if (status.status === 'failed') {
          thread.push({
            role: 'agent',
            html: renderMarkdown(`**The agent call failed.** ${status.error ?? ''}`),
          });
          this.sending = false;
          this.scrollToBottom();
        }
      },
      error: (error) => {
        thread.push({
          role: 'agent',
          html: renderMarkdown(`**Could not reach the API.** ${error?.message ?? ''}`),
        });
        this.sending = false;
        this.scrollToBottom();
      },
    });
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      const element = this.transcript?.nativeElement;
      if (element) {
        element.scrollTop = element.scrollHeight;
      }
    }, 50);
  }
}
