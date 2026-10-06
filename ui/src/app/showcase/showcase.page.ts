import { CommonModule } from '@angular/common';
import { AfterViewInit, Component, ElementRef, ViewChild, computed, inject, signal } from '@angular/core';
import { DomSanitizer } from '@angular/platform-browser';
import { IonIcon, IonToggle } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import {
  alertCircleOutline,
  analyticsOutline,
  arrowForwardOutline,
  documentTextOutline,
  expandOutline,
  imagesOutline,
  layersOutline,
  listOutline,
  lockClosedOutline,
  openOutline,
  playCircleOutline,
  sparklesOutline,
  volumeHighOutline,
} from 'ionicons/icons';

import { SHOWCASE_CONFIG } from './showcase.config';

type ShowcaseTab = 'videos' | 'walkthrough' | 'business-case' | 'features' | 'architecture';
type ShowcaseExperience = 'copilot-studio' | 'foundry';

interface ShowcaseTabItem {
  id: ShowcaseTab;
  label: string;
  icon: string;
}

interface VideoItem {
  sequence: string;
  title: string;
  description: string;
  duration: string;
  file?: string;
  comingSoon?: boolean;
}

interface FeatureItem {
  icon: string;
  title: string;
  description: string;
}

interface MetricItem {
  value: string;
  label: string;
  detail: string;
}

interface ScenarioRow {
  assumption: string;
  pilot: string;
  businessUnit: string;
  enterprise: string;
}

interface UseCaseItem {
  team: string;
  focus: string;
  output: string;
}

type ValueScenarioId = 'pilot' | 'business-unit' | 'enterprise';

interface ValueScenario {
  id: ValueScenarioId;
  label: string;
  selectorLabel: string;
  users: string;
  annualBenefit: string;
  netMonthly: string;
  roi: string;
  payback: string;
  relative: number;
  isDefault?: boolean;
}

@Component({
  selector: 'app-showcase',
  standalone: true,
  imports: [CommonModule, IonIcon, IonToggle],
  templateUrl: './showcase.page.html',
  styleUrl: './showcase.page.scss',
})
export class ShowcasePage implements AfterViewInit {
  @ViewChild('videoPlayer') private videoPlayer?: ElementRef<HTMLVideoElement>;
  @ViewChild('videoFrame') private videoFrame?: ElementRef<HTMLElement>;

  private readonly sanitizer = inject(DomSanitizer);

  readonly experience = signal<ShowcaseExperience>('copilot-studio');
  readonly activeTab = signal<ShowcaseTab>('videos');
  readonly selectedVideoIndex = signal(0);
  readonly autoplayNext = signal(true);
  readonly autoplayBlocked = signal(false);
  readonly videoError = signal(false);

  readonly isFoundry = computed(() => this.experience() === 'foundry');
  readonly heroTitle = computed(() =>
    this.isFoundry()
      ? 'Private Microsoft Foundry agent for Azure Databricks Genie'
      : 'High-fidelity PowerPoint from private Azure Databricks data',
  );
  readonly heroDescription = computed(() =>
    this.isFoundry()
      ? 'A pro-code Microsoft Foundry prompt agent runs in Microsoft Teams through Azure Bot Service, calls a private API Management MCP endpoint, and preserves the signed-in user identity all the way to Databricks Genie.'
      : 'A Copilot Studio agent answers business questions over Unity Catalog through AI/BI Genie and returns a real, executive-ready PowerPoint file — with Databricks and API Management both locked to private network access only.',
  );
  readonly repoUrl = computed(() =>
    this.isFoundry() ? SHOWCASE_CONFIG.foundry.repositoryUrl : SHOWCASE_CONFIG.copilotStudio.repositoryUrl,
  );
  readonly setupGuideUrl = computed(() =>
    this.isFoundry() ? SHOWCASE_CONFIG.foundry.setupGuideUrl : SHOWCASE_CONFIG.copilotStudio.setupGuideUrl,
  );
  readonly oboGuideUrl = computed(() =>
    this.isFoundry() ? SHOWCASE_CONFIG.foundry.oboGuideUrl : SHOWCASE_CONFIG.copilotStudio.oboGuideUrl,
  );
  readonly skillUrl = SHOWCASE_CONFIG.copilotStudio.skillUrl;
  readonly highLevelArchitectureImageUrl = SHOWCASE_CONFIG.copilotStudio.highLevelArchitectureImageUrl;
  readonly architectureImageUrl = SHOWCASE_CONFIG.copilotStudio.architectureImageUrl;
  readonly oboArchitectureImageUrl = SHOWCASE_CONFIG.copilotStudio.oboArchitectureImageUrl;
  readonly foundryArchitecture = SHOWCASE_CONFIG.foundry.architecture;
  readonly businessCasePdfUrl = SHOWCASE_CONFIG.copilotStudio.businessCase.pdfUrl;
  readonly businessCasePptxUrl = SHOWCASE_CONFIG.copilotStudio.businessCase.pptxUrl;
  readonly businessCaseFolderUrl = SHOWCASE_CONFIG.copilotStudio.businessCase.folderUrl;
  readonly copilotStudioUrl = SHOWCASE_CONFIG.copilotStudio.productUrl;
  readonly linkedInUrl = SHOWCASE_CONFIG.contact.linkedInUrl;
  readonly contactUrl = SHOWCASE_CONFIG.contact.emailUrl;

  readonly tabs: ShowcaseTabItem[] = [
    { id: 'videos', label: 'Video series', icon: 'play-circle-outline' },
    { id: 'walkthrough', label: 'Walkthrough', icon: 'images-outline' },
    { id: 'business-case', label: 'Business case', icon: 'analytics-outline' },
    { id: 'features', label: 'Features', icon: 'sparkles-outline' },
    { id: 'architecture', label: 'Architecture', icon: 'layers-outline' },
  ];

  readonly copilotVideos: VideoItem[] = [
    {
      sequence: '01',
      title: 'Architecture overview',
      description:
        'How Microsoft 365 Copilot, Copilot Studio, API Management, and Azure Databricks work together to create high-fidelity PowerPoint presentations from governed data.',
      duration: '6:14',
      file: '01. Architecure Overview - High Fidelity Powerpoint in Databricks.mp4',
    },
    {
      sequence: '02',
      title: 'Network infrastructure requirements',
      description:
        'The delegated subnets, virtual network peerings, private endpoints, private DNS, and enterprise policy required for the private data path.',
      duration: '6:51',
      file: '02. Network Infra requirements.mp4',
    },
    {
      sequence: '03',
      title: 'MCP security and API Gateway',
      description:
        'Securing model tool calls through API Management, private networking, managed identity, and centralized API gateway controls.',
      duration: '3:37',
      file: '03. MCP security and API Gateway.mp4',
    },
    {
      sequence: '04',
      title: 'Building Databricks custom connectors',
      description:
        'Building Power Platform custom connectors that expose the private Databricks operations to Copilot Studio.',
      duration: '2:50',
      file: '04. Building Custom Connectors for Databricks in Copilot - PowerPlatform.mp4',
    },
    {
      sequence: '05',
      title: 'Building the Copilot Studio agent',
      description:
        'Creating the agent on the GitHub Copilot harness, attaching the four Genie tools, and uploading the executive deck skill.',
      duration: '10:22',
      file: '05. Building  the Agent in Copilot Studio.mp4',
    },
    {
      sequence: '06',
      title: 'Publishing the agent to Microsoft 365',
      description:
        'Publishing the Copilot Studio agent to Microsoft 365 Copilot and Teams so users can access it in their daily workflow.',
      duration: '7:43',
      file: '06. Publishing the Agent from Copilot Studio to M365 Copilot and Teams.mp4',
    },
    {
      sequence: '07',
      title: 'Authentication, OBO, and token exchange',
      description:
        'How the signed-in user token flows through API Management and the private broker, then exchanges into a Databricks token that preserves the user identity and Unity Catalog permissions.',
      duration: '18:47',
      file: '07. Authentication - OBO flow and JWT to DBX Token Exchange.mp4',
    },
    {
      sequence: '08',
      title: 'Updating the agent with OBO',
      description:
        'Updating the Copilot Studio agent to use the delegated-user connector, end-user credentials, and the new on-behalf-of authentication flow.',
      duration: '10:14',
      file: '08. Updating Agent with OBO Flow.mp4',
    },
    {
      sequence: '09',
      title: 'Business case and value proposition',
      description:
        'The expected productivity gains, implementation costs, return on investment, and broader business value of the solution.',
      duration: '3:18',
      file: '09. Business Case and Value Proposition.mp4',
    },
  ];

  readonly copilotFeatures: FeatureItem[] = [
    {
      icon: 'lock-closed-outline',
      title: 'Fully private data path',
      description:
        'Databricks and API Management both have public network access disabled. Traffic flows through delegated subnets, virtual network peering, and private endpoints only.',
    },
    {
      icon: 'sparkles-outline',
      title: 'Natural language over Unity Catalog',
      description:
        'AI/BI Genie resolves business questions into governed SQL against a curated schema, returning grounded rows with the generated SQL.',
    },
    {
      icon: 'document-text-outline',
      title: 'Real PowerPoint files',
      description:
        'The agent writes an actual .pptx in a governed sandbox with native chart objects, tables, KPI tiles, and a shapes-based diagram, then verifies it before returning a download card.',
    },
    {
      icon: 'lock-closed-outline',
      title: 'No secrets in Power Platform',
      description:
        'API Management authenticates to Databricks with its managed identity. No Databricks token or key is ever stored in the connector or the agent.',
    },
    {
      icon: 'analytics-outline',
      title: 'Traceable end to end',
      description:
        'Every gateway call lands in Log Analytics with its response and backend response code, so a full deck run can be reconciled request by request.',
    },
    {
      icon: 'layers-outline',
      title: 'Portable deck specification',
      description:
        'Four core slides plus optional sections chosen from the data, branding, and chart fidelity rules live in a reusable SKILL.md that can be uploaded to any agent on the same harness.',
    },
  ];

  readonly foundryFeatures: FeatureItem[] = [
    {
      icon: 'sparkles-outline',
      title: 'Pro-code Foundry prompt agent',
      description:
        'A versioned Microsoft Foundry prompt agent uses the Responses API and a project-scoped MCP connection for explicit, automatable agent lifecycle management.',
    },
    {
      icon: 'lock-closed-outline',
      title: 'Delegated user authorization',
      description:
        'Teams sign-in, Foundry user identity, APIM OAuth validation, and Databricks RFC 8693 token exchange preserve the user principal and fail closed.',
    },
    {
      icon: 'layers-outline',
      title: 'Teams and Azure Bot integration',
      description:
        'A lightweight TypeScript bridge handles Bot Framework activities, OAuth prompts, Foundry responses, consent links, and Teams conversation continuity.',
    },
    {
      icon: 'lock-closed-outline',
      title: 'Private governed data path',
      description:
        'Foundry reaches the APIM-hosted MCP server privately, and Databricks Genie continues to enforce workspace and Unity Catalog permissions for each user.',
    },
    {
      icon: 'analytics-outline',
      title: 'Observable end to end',
      description:
        'Bot diagnostics, APIM logs, Foundry response details, and Databricks audit events support correlated operational and security verification.',
    },
    {
      icon: 'layers-outline',
      title: 'Bicep and Terraform deployment',
      description:
        'Equivalent infrastructure definitions provision the bot, App Service, monitoring, RBAC, and OBO MCP facade for repeatable enterprise deployment.',
    },
  ];

  readonly features = computed(() => (this.isFoundry() ? this.foundryFeatures : this.copilotFeatures));

  readonly videos = computed<readonly VideoItem[]>(() =>
    this.isFoundry() ? SHOWCASE_CONFIG.foundry.videos : this.copilotVideos,
  );
  readonly videoStats = computed(() =>
    this.isFoundry() ? SHOWCASE_CONFIG.foundry.videoStats : SHOWCASE_CONFIG.copilotStudio.videoStats,
  );
  readonly walkthrough = computed(() =>
    this.isFoundry() ? SHOWCASE_CONFIG.foundry.walkthrough : SHOWCASE_CONFIG.copilotStudio.walkthrough,
  );

  readonly selectedVideo = computed(() => this.videos()[this.selectedVideoIndex()] ?? this.videos()[0]);
  readonly selectedVideoSrc = computed(() => {
    const file = this.selectedVideo().file;
    return file ? `${SHOWCASE_CONFIG.copilotStudio.mediaRoot}/${encodeURIComponent(file)}` : null;
  });

  readonly businessCaseEmbedUrl = computed(() =>
    this.sanitizer.bypassSecurityTrustResourceUrl(`${this.businessCasePdfUrl}#view=FitH`),
  );

  // Figures below mirror the business-unit scenario in the published business case deck.
  readonly businessMetrics: MetricItem[] = [
    { value: '$892.5K', label: 'Annual run-rate benefit', detail: 'Before one-time implementation cost' },
    { value: '243%', label: 'Year-one ROI', detail: 'Net benefit divided by total year-one cost' },
    { value: '2.4 months', label: 'Estimated payback', detail: 'At 100 active business users' },
    { value: '$74.4K', label: 'Net monthly benefit', detail: 'Capacity value less recurring cost' },
    { value: '1,125', label: 'Productive hours released monthly', detail: '$84.4K of monthly capacity value' },
    { value: '60%', label: 'Less employee time per deck', detail: 'Five hours down to two' },
  ];

  readonly scenarios: ScenarioRow[] = [
    { assumption: 'Active users', pilot: '25', businessUnit: '100', enterprise: '300' },
    { assumption: 'Decks per user per month', pilot: '4', businessUnit: '5', enterprise: '5' },
    { assumption: 'Hours saved per deck', pilot: '2.5', businessUnit: '3.0', enterprise: '3.5' },
    { assumption: 'Loaded labor cost', pilot: '$75/hour', businessUnit: '$75/hour', enterprise: '$75/hour' },
    { assumption: 'Productive usage factor', pilot: '70%', businessUnit: '75%', enterprise: '80%' },
    { assumption: 'Monthly operating cost', pilot: '$5,000', businessUnit: '$10,000', enterprise: '$25,000' },
    { assumption: 'One-time implementation', pilot: '$60,000', businessUnit: '$175,000', enterprise: '$350,000' },
  ];

  readonly useCases: UseCaseItem[] = [
    { team: 'Sales', focus: 'Pipeline reviews', output: 'Account plans and forecast decks' },
    { team: 'Finance', focus: 'Performance analysis', output: 'Budget and variance decks' },
    { team: 'Supply chain', focus: 'Inventory and demand', output: 'Supplier and fulfillment reviews' },
    { team: 'Operations', focus: 'Service and quality', output: 'Weekly operating reviews' },
    { team: 'Product', focus: 'Portfolio performance', output: 'Launch and adoption updates' },
    { team: 'Leadership', focus: 'Cross-functional metrics', output: 'Executive and board briefings' },
  ];

  // Derived from the assumption table using the deck's formula:
  // users x decks x hours saved x loaded cost x productive usage, less operating cost.
  readonly valueScenarios: ValueScenario[] = [
    {
      id: 'pilot',
      label: 'Pilot',
      selectorLabel: 'Pilot',
      users: '25 users',
      annualBenefit: '$97.5K',
      netMonthly: '$8.1K',
      roi: '31%',
      payback: '7.4 months',
      relative: 3,
    },
    {
      id: 'business-unit',
      label: 'Business unit',
      selectorLabel: 'Business',
      users: '100 users',
      annualBenefit: '$892.5K',
      netMonthly: '$74.4K',
      roi: '243%',
      payback: '2.4 months',
      relative: 26,
      isDefault: true,
    },
    {
      id: 'enterprise',
      label: 'Enterprise',
      selectorLabel: 'Enterprise',
      users: '300 users',
      annualBenefit: '$3.48M',
      netMonthly: '$290K',
      roi: '482%',
      payback: '1.2 months',
      relative: 100,
    },
  ];

  readonly selectedValueScenarioId = signal<ValueScenarioId>('business-unit');
  readonly selectedValueScenario = computed(
    () =>
      this.valueScenarios.find((scenario) => scenario.id === this.selectedValueScenarioId()) ??
      this.valueScenarios[1],
  );

  constructor() {
    addIcons({
      alertCircleOutline,
      analyticsOutline,
      arrowForwardOutline,
      documentTextOutline,
      expandOutline,
      imagesOutline,
      layersOutline,
      listOutline,
      lockClosedOutline,
      openOutline,
      playCircleOutline,
      sparklesOutline,
      volumeHighOutline,
    });
  }

  ngAfterViewInit(): void {
    this.playSelectedVideo();
  }

  setTab(tab: ShowcaseTab): void {
    this.activeTab.set(tab);
  }

  setExperience(experience: ShowcaseExperience): void {
    if (this.experience() === experience) {
      return;
    }
    this.experience.set(experience);
    this.selectedVideoIndex.set(0);
    this.videoError.set(false);
    this.autoplayBlocked.set(false);
    if (experience === 'copilot-studio' && this.activeTab() === 'videos') {
      queueMicrotask(() => this.playSelectedVideo());
    }
  }

  setValueScenario(id: ValueScenarioId): void {
    this.selectedValueScenarioId.set(id);
  }

  selectVideo(index: number): void {
    if (index < 0 || index >= this.videos().length) {
      return;
    }
    this.selectedVideoIndex.set(index);
    this.videoError.set(false);
    this.autoplayBlocked.set(false);
    this.playSelectedVideo();
  }

  playNext(): void {
    if (!this.autoplayNext()) {
      return;
    }
    const next = this.selectedVideoIndex() + 1;
    if (next < this.videos().length) {
      this.selectVideo(next);
    }
  }

  setAutoplayNext(event: CustomEvent): void {
    this.autoplayNext.set(Boolean((event.detail as { checked?: boolean })?.checked));
  }

  playSelectedVideo(): void {
    const element = this.videoPlayer?.nativeElement;
    if (!element) {
      return;
    }
    const source = this.selectedVideoSrc();
    if (!source) {
      element.pause();
      element.removeAttribute('src');
      element.load();
      return;
    }
    if (element.src !== source || element.error) {
      element.src = source;
      element.load();
    }
    element.muted = false;
    element
      .play()
      .then(() => {
        if (element.src === source) this.autoplayBlocked.set(false);
      })
      .catch((error: DOMException) => {
        if (element.src === source && error.name === 'NotAllowedError') {
          this.autoplayBlocked.set(true);
        }
      });
  }

  onVideoCanPlay(): void {
    this.videoError.set(false);
  }

  onVideoError(): void {
    this.videoError.set(true);
  }

  enterFullscreen(): void {
    this.videoFrame?.nativeElement.requestFullscreen?.().catch(() => undefined);
  }
}
