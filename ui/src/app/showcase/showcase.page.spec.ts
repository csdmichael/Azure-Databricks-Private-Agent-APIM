import { ComponentFixture, TestBed } from '@angular/core/testing';

import { SHOWCASE_CONFIG } from './showcase.config';
import { ShowcasePage } from './showcase.page';

describe('ShowcasePage', () => {
  let fixture: ComponentFixture<ShowcasePage>;
  let component: ShowcasePage;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [ShowcasePage],
    }).compileComponents();

    fixture = TestBed.createComponent(ShowcasePage);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('starts with the Copilot Studio low-code showcase', () => {
    expect(component.experience()).toBe('copilot-studio');
    expect(component.repoUrl()).toBe(SHOWCASE_CONFIG.copilotStudio.repositoryUrl);
    expect(component.features()).toBe(component.copilotFeatures);
  });

  it('switches every shared content source to Foundry', () => {
    component.setExperience('foundry');

    expect(component.heroTitle()).toContain('Microsoft Foundry');
    expect(component.repoUrl()).toBe(SHOWCASE_CONFIG.foundry.repositoryUrl);
    expect(component.setupGuideUrl()).toBe(SHOWCASE_CONFIG.foundry.setupGuideUrl);
    expect(component.oboGuideUrl()).toBe(SHOWCASE_CONFIG.foundry.oboGuideUrl);
    expect(component.features()).toBe(component.foundryFeatures);
    expect(component.videos()).toBe(SHOWCASE_CONFIG.foundry.videos);
    expect(component.selectedVideo().file).toContain('assets/foundry/videos/Teams%20Agent%20-%20Bot%20-%20Foundry');
    expect(component.selectedVideo().duration).toBe('11:38');
    expect(component.selectedVideo().comingSoon).toBeUndefined();
    expect(component.videos().slice(1).every((video) => video.comingSoon)).toBeTrue();
    expect(component.walkthrough()).toBe(SHOWCASE_CONFIG.foundry.walkthrough);
  });
});
