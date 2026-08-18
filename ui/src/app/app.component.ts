import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';

import { ApiService } from './core/api.service';
import { environment } from '../environments/environment';

@Component({
  selector: 'app-root',
  templateUrl: 'app.component.html',
  styleUrls: ['app.component.scss'],
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
})
export class AppComponent {
  readonly githubRepoUrl = environment.githubRepoUrl;
  readonly swaggerUrl: string;
  readonly redocUrl: string;

  constructor(api: ApiService) {
    this.swaggerUrl = `${api.baseUrl}/docs`;
    this.redocUrl = `${api.baseUrl}/redoc`;
  }
}
