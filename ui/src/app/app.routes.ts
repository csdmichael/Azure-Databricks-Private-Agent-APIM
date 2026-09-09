import { Routes } from '@angular/router';

export const APP_ROUTES: Routes = [
  {
    path: 'showcase',
    loadComponent: () => import('./showcase/showcase.page').then((m) => m.ShowcasePage),
  },
  {
    path: 'chat',
    loadComponent: () => import('./chat/chat.page').then((m) => m.ChatPage),
  },
  {
    path: 'packages',
    loadComponent: () => import('./packages/packages.page').then((m) => m.PackagesPage),
  },
  { path: '', redirectTo: 'showcase', pathMatch: 'full' },
  { path: '**', redirectTo: 'showcase' },
];
