import { Routes } from '@angular/router';

export const APP_ROUTES: Routes = [
  {
    path: 'chat',
    loadComponent: () => import('./chat/chat.page').then((m) => m.ChatPage),
  },
  {
    path: 'packages',
    loadComponent: () => import('./packages/packages.page').then((m) => m.PackagesPage),
  },
  { path: '', redirectTo: 'chat', pathMatch: 'full' },
  { path: '**', redirectTo: 'chat' },
];
