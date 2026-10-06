import { Routes } from '@angular/router';

export const APP_ROUTES: Routes = [
  {
    path: 'history',
    loadComponent: () => import('./stats/history.page').then((module) => module.HistoryPage),
  },
  {
    path: 'stats',
    loadComponent: () => import('./stats/stats.page').then((module) => module.StatsPage),
  },
  {
    path: 'privacy',
    loadComponent: () => import('./stats/privacy.page').then((module) => module.PrivacyPage),
  },
  {
    path: 'showcase',
    loadComponent: () => import('./showcase/showcase.page').then((m) => m.ShowcasePage),
  },
  {
    path: 'packages',
    loadComponent: () => import('./packages/packages.page').then((m) => m.PackagesPage),
  },
  { path: '', redirectTo: 'showcase', pathMatch: 'full' },
  { path: '**', redirectTo: 'showcase' },
];
