import { FOUNDRY_VIDEOS } from './foundry-videos.generated';

const repositoryRoot = 'https://github.com/csdmichael/Azure-Databricks-Private-Agent-APIM';
const rawRepositoryRoot = 'https://raw.githubusercontent.com/csdmichael/Azure-Databricks-Private-Agent-APIM/main';
const foundryRepositoryUrl = `${repositoryRoot}/tree/main/foundry`;
const foundryAssets = 'assets/foundry';
const copilotStudioAssets = 'assets/copilot-studio';
const businessCaseAssets = 'assets/business-case';
const businessCaseFile = 'private-data-to-powerpoint-business-case-final';
const foundryComingSoonVideos = [
  {
    sequence: '02',
    title: 'Building and publishing the Foundry agent',
    description:
      'Creating the prompt agent, attaching the private MCP connection, publishing a version, and validating the agent in Microsoft Foundry.',
    duration: 'Coming soon',
    comingSoon: true,
  },
  {
    sequence: '03',
    title: 'Teams, Bot Service, and OAuth',
    description:
      'Packaging the Teams app, configuring Azure Bot Service, and carrying the signed-in user context into the Foundry Responses API.',
    duration: 'Coming soon',
    comingSoon: true,
  },
  {
    sequence: '04',
    title: 'APIM OBO and Databricks governance',
    description:
      'Validating the delegated token in API Management, exchanging it for Databricks, and proving Unity Catalog enforcement and audit correlation.',
    duration: 'Coming soon',
    comingSoon: true,
  },
];

export const SHOWCASE_CONFIG = {
  copilotStudio: {
    repositoryUrl: repositoryRoot,
    setupGuideUrl: `${repositoryRoot}/blob/main/docs/setup-guide.md`,
    oboGuideUrl: `${repositoryRoot}/blob/main/docs/obo/README.md`,
    skillUrl: `${repositoryRoot}/blob/main/skills/executive-deck-builder/SKILL.md`,
    highLevelArchitectureImageUrl: 'assets/architecture/HL%20Architecture.png',
    architectureImageUrl: `${rawRepositoryRoot}/docs/azure-databricks-private-agent-apim-architecture.png`,
    oboArchitectureImageUrl: 'assets/architecture/Databricks-OBO-Token-Exchange.png',
    mediaRoot: `https://media.githubusercontent.com/media/csdmichael/Azure-Databricks-Private-Agent-APIM/main/docs/Videos`,
    businessCase: {
      pdfUrl: `${businessCaseAssets}/${businessCaseFile}.pdf`,
      pptxUrl: `${businessCaseAssets}/${businessCaseFile}.pptx`,
      folderUrl: `${repositoryRoot}/tree/main/docs/Business%20Case`,
    },
    productUrl: 'https://copilotstudio.microsoft.com/',
    videoStats: [
      { value: '0', label: 'Public endpoints' },
      { value: '60%', label: 'Less time per deck' },
      { value: '100%', label: 'Figures traced to source' },
    ],
    walkthrough: {
      kicker: 'Copilot Studio implementation walkthrough',
      title: 'From private connector to executive-ready deck',
      description:
        'Follow the low-code implementation from private API Management networking through the Power Platform connector, Copilot Studio agent, and delivered PowerPoint.',
      resources: [
        {
          title: 'Private API gateway',
          description: 'Configure API Management private networking and private endpoint access.',
          image: `${copilotStudioAssets}/07.01-apim-private-networking.png`,
          url: `${repositoryRoot}/blob/main/docs/setup-guide.md`,
        },
        {
          title: 'Power Platform connector',
          description: 'Expose the governed Databricks operations through the custom connector.',
          image: `${copilotStudioAssets}/10-powerapps-custom-connector.png`,
          url: `${repositoryRoot}/blob/main/docs/setup-guide.md`,
        },
        {
          title: 'Copilot Studio agent',
          description: 'Build the low-code agent and connect the Databricks tools and deck skill.',
          image: `${copilotStudioAssets}/14-agent-build.png`,
          url: `${repositoryRoot}/blob/main/docs/setup-guide.md`,
        },
        {
          title: 'PowerPoint delivery',
          description: 'Return the verified executive deck directly to the user conversation.',
          image: `${copilotStudioAssets}/15-deck-delivered.png`,
          url: `${repositoryRoot}/blob/main/docs/setup-guide.md`,
        },
      ],
    },
  },
  foundry: {
    repositoryUrl: foundryRepositoryUrl,
    setupGuideUrl: `${foundryRepositoryUrl}#setup-guide`,
    oboGuideUrl: `${repositoryRoot}/blob/main/foundry/docs/obo/README.md`,
    videos: [
      ...FOUNDRY_VIDEOS,
      ...foundryComingSoonVideos.slice(Math.max(FOUNDRY_VIDEOS.length - 1, 0)),
    ],
    videoStats: [
      { value: '0', label: 'Databricks PATs' },
      { value: '1:1', label: 'User authorization' },
      { value: '100%', label: 'Private data path' },
    ],
    architecture: {
      imageUrl: `${foundryAssets}/Teams-Bot-Foundry-APIM-Databricks-OboFlow-Architecture.png`,
      imageAlt:
        'Private Microsoft Foundry agent in Teams calling Azure Databricks Genie through an API Management MCP gateway with on-behalf-of user delegation',
      caption:
        'The signed-in Teams user remains the authorized principal from the conversation through Foundry, API Management, and Databricks Genie. Private endpoints isolate the data path, while APIM performs policy enforcement and the delegated token exchange.',
      overview:
        'This design separates the public conversational edge from the private data plane. Teams and Azure Bot Service handle the user conversation; Microsoft Foundry orchestrates the prompt agent; API Management governs the MCP call; and Databricks Genie executes against Unity Catalog as the signed-in user.',
      flow: [
        {
          step: '1',
          title: 'User sign-in',
          description: 'The user signs in from Microsoft Teams with Microsoft Entra ID.',
        },
        {
          step: '2–3',
          title: 'Teams to Foundry',
          description:
            'Azure Bot Service validates the activity, manages the user identity, and invokes the Foundry prompt agent with delegated user context.',
        },
        {
          step: '4–6',
          title: 'Foundry through APIM',
          description:
            'Foundry calls the private APIM MCP gateway. APIM validates JWT claims, applies rate limits and audit logging, then performs the OAuth 2.0 OBO exchange.',
        },
        {
          step: '7',
          title: 'Databricks execution',
          description:
            'APIM forwards a short-lived delegated Databricks token. Genie executes under the user’s RBAC and Unity Catalog permissions.',
        },
        {
          step: '8',
          title: 'Governed response',
          description:
            'The grounded Genie result returns through APIM, Foundry, and Azure Bot Service to the originating Teams conversation.',
        },
      ],
      controls: [
        {
          title: 'Private networking',
          description:
            'Foundry, APIM, and Databricks use private endpoints, private DNS, and disabled public data-plane access inside the Azure virtual network.',
        },
        {
          title: 'User-delegated OBO',
          description:
            'APIM exchanges the incoming user assertion for a short-lived Databricks access token. Foundry never receives or stores a Databricks PAT.',
        },
        {
          title: 'Policy and governance',
          description:
            'APIM validates issuer, audience, tenant, scope, and user identity; Databricks enforces workspace RBAC and Unity Catalog governance.',
        },
        {
          title: 'Security operations',
          description:
            'Microsoft Entra ID, Key Vault, Azure Monitor, Log Analytics, and centralized audit events support identity, secret, and telemetry operations.',
        },
      ],
    },
    walkthrough: {
      kicker: 'Foundry implementation walkthrough',
      title: 'From prompt agent to governed Databricks response',
      description:
        'Follow the pro-code implementation from the configured Foundry agent through Azure Bot Service, delegated OAuth, and the final Teams experience.',
      resources: [
        {
          title: 'Foundry agent configuration',
          description: 'Review the prompt agent, model deployment, instructions, and custom OAuth MCP connection.',
          image: `${foundryAssets}/01-foundry-agent.png`,
          url: `${repositoryRoot}/blob/main/foundry/README.md#architecture`,
        },
        {
          title: 'Azure Bot Service',
          description: 'See the Teams channel and Azure Bot integration that exposes the Foundry agent to end users.',
          image: `${foundryAssets}/02-bot-service.png`,
          url: `${foundryRepositoryUrl}#setup-guide`,
        },
        {
          title: 'Grounded Genie response',
          description: 'Inspect a test Web Chat response grounded in Databricks Genie data after delegated OAuth consent.',
          image: `${foundryAssets}/03-bot-web-chat.png`,
          url: `${repositoryRoot}/blob/main/foundry/docs/obo/README.md#live-web-chat-verification`,
        },
        {
          title: 'Teams experience',
          description: 'View the packaged Teams app returning the Foundry response in the user conversation.',
          image: `${foundryAssets}/04-teams-chat.png`,
          url: `${repositoryRoot}/blob/main/foundry/README.md#playwright-screenshots`,
        },
      ],
    },
  },
  contact: {
    linkedInUrl: 'https://www.linkedin.com/in/michael-yaacoub-7a46436/',
    emailUrl:
      'mailto:myaacoub@microsoft.com?subject=Azure%20Databricks%20Private%20Agent%20-%20request&body=Hello%20Michael%2C%0D%0A%0D%0AI%20would%20like%20to%20learn%20more%20about%20the%20private%20Databricks%20agent%20solution.%0D%0A%0D%0AName%3A%0D%0AOrganization%3A%0D%0AUse%20case%3A%0D%0A',
  },
} as const;
