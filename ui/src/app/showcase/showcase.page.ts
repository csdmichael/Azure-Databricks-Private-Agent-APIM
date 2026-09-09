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
  layersOutline,
  listOutline,
  lockClosedOutline,
  openOutline,
  playCircleOutline,
  sparklesOutline,
  volumeHighOutline,
} from 'ionicons/icons';

type ShowcaseTab = 'videos' | 'business-case' | 'features' | 'architecture';

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
  file: string;
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

const REPO_ROOT = 'https://github.com/csdmichael/Azure-Databricks-Private-Agent-APIM';
const RAW_ROOT = 'https://raw.githubusercontent.com/csdmichael/Azure-Databricks-Private-Agent-APIM/main';
const MEDIA_ROOT = `https://media.githubusercontent.com/media/csdmichael/Azure-Databricks-Private-Agent-APIM/main/docs/Videos`;
const BUSINESS_CASE_ASSETS = 'assets/business-case';
const BUSINESS_CASE_FILE = 'private-data-to-powerpoint-business-case-final';

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

  readonly activeTab = signal<ShowcaseTab>('videos');
  readonly selectedVideoIndex = signal(0);
  readonly autoplayNext = signal(true);
  readonly autoplayBlocked = signal(false);
  readonly videoError = signal(false);

  readonly repoUrl = REPO_ROOT;
  readonly setupGuideUrl = `${REPO_ROOT}/blob/main/docs/setup-guide.md`;
  readonly skillUrl = `${REPO_ROOT}/blob/main/skills/executive-deck-builder/SKILL.md`;
  readonly architectureImageUrl = `${RAW_ROOT}/docs/azure-databricks-private-agent-apim-architecture.png`;
  readonly businessCasePdfUrl = `${BUSINESS_CASE_ASSETS}/${BUSINESS_CASE_FILE}.pdf`;
  readonly businessCasePptxUrl = `${BUSINESS_CASE_ASSETS}/${BUSINESS_CASE_FILE}.pptx`;
  readonly businessCaseFolderUrl = `${REPO_ROOT}/tree/main/docs/Business%20Case`;
  readonly copilotStudioUrl = 'https://copilotstudio.microsoft.com/';
  readonly linkedInUrl = 'https://www.linkedin.com/in/michael-yaacoub-7a46436/';
  readonly contactUrl =
    'mailto:myaacoub@microsoft.com?subject=Azure%20Databricks%20Private%20Agent%20-%20request&body=Hello%20Michael%2C%0D%0A%0D%0AI%20would%20like%20to%20learn%20more%20about%20the%20private%20Databricks%20agent%20solution.%0D%0A%0D%0AName%3A%0D%0AOrganization%3A%0D%0AUse%20case%3A%0D%0A';

  readonly tabs: ShowcaseTabItem[] = [
    { id: 'videos', label: 'Video series', icon: 'play-circle-outline' },
    { id: 'business-case', label: 'Business case', icon: 'analytics-outline' },
    { id: 'features', label: 'Features', icon: 'sparkles-outline' },
    { id: 'architecture', label: 'Architecture', icon: 'layers-outline' },
  ];

  // Placeholder entries. Drop the matching files into docs/Videos to activate them.
  readonly videos: VideoItem[] = [
    {
      sequence: '01',
      title: 'Solution overview',
      description:
        'What the solution does end to end: a natural-language question in Microsoft 365 Copilot returns an executive PowerPoint built from private Databricks data.',
      duration: 'Coming soon',
      file: '01-solution-overview.mp4',
    },
    {
      sequence: '02',
      title: 'Private networking walkthrough',
      description:
        'Delegated subnets, virtual network peering, private DNS, and the enterprise policy that injects Power Platform into the network.',
      duration: 'Coming soon',
      file: '02-private-networking.mp4',
    },
    {
      sequence: '03',
      title: 'API Management and Databricks',
      description:
        'Publishing the Genie API, locking the gateway to its private endpoint, and authenticating to Databricks with a managed identity.',
      duration: 'Coming soon',
      file: '03-apim-databricks.mp4',
    },
    {
      sequence: '04',
      title: 'The custom connector',
      description:
        'Importing the Swagger definition, configuring API key security, and why a custom connector is required instead of an MCP server.',
      duration: 'Coming soon',
      file: '04-custom-connector.mp4',
    },
    {
      sequence: '05',
      title: 'Building the Copilot Studio agent',
      description:
        'Creating the agent on the GitHub Copilot harness, attaching the four Genie tools, and uploading the executive deck skill.',
      duration: 'Coming soon',
      file: '05-copilot-studio-agent.mp4',
    },
    {
      sequence: '06',
      title: 'Generating the deck',
      description:
        'A live run: three Genie queries, a verified nine-slide PowerPoint with native charts, and the download card in chat.',
      duration: 'Coming soon',
      file: '06-deck-generation.mp4',
    },
  ];

  readonly features: FeatureItem[] = [
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

  readonly selectedVideo = computed(() => this.videos[this.selectedVideoIndex()]);
  readonly selectedVideoSrc = computed(() => `${MEDIA_ROOT}/${this.selectedVideo().file}`);

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

  setValueScenario(id: ValueScenarioId): void {
    this.selectedValueScenarioId.set(id);
  }

  selectVideo(index: number): void {
    if (index < 0 || index >= this.videos.length) {
      return;
    }
    this.selectedVideoIndex.set(index);
    this.videoError.set(false);
    this.autoplayBlocked.set(false);
    queueMicrotask(() => this.playSelectedVideo());
  }

  playNext(): void {
    if (!this.autoplayNext()) {
      return;
    }
    const next = this.selectedVideoIndex() + 1;
    if (next < this.videos.length) {
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
    element.muted = false;
    element
      .play()
      .then(() => this.autoplayBlocked.set(false))
      .catch(() => this.autoplayBlocked.set(true));
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
