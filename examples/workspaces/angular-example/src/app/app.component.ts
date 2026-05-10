import { Component, signal } from '@angular/core'

@Component({
  selector: 'app-root',
  standalone: true,
  template: `
    <main style="font-family:system-ui;padding:2rem">
      <h1>Hello from Angular in CodingBooth!</h1>
      <p>Click the button to confirm Angular signals work:</p>
      <button (click)="count.update((c) => c + 1)">
        Clicked {{ count() }} time{{ count() === 1 ? '' : 's' }}
      </button>
    </main>
  `,
})
export class AppComponent {
  count = signal(0)
}
