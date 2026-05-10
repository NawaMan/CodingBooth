import { Component, OnInit, inject, signal } from '@angular/core'
import { HttpClient } from '@angular/common/http'

interface Item { _id: string; message: string }

@Component({
  selector: 'app-root',
  standalone: true,
  template: `
    <main style="font-family:system-ui;padding:2rem">
      <h1>Hello from MEAN in CodingBooth!</h1>
      <p>Items from the Express API (which reads MongoDB):</p>
      <ul>
        @for (item of items(); track item._id) {
          <li>{{ item.message }}</li>
        }
      </ul>
    </main>
  `,
})
export class AppComponent implements OnInit {
  private http = inject(HttpClient)
  items = signal<Item[]>([])

  ngOnInit() {
    this.http.get<Item[]>('http://localhost:3000/api/items').subscribe((data) => this.items.set(data))
  }
}
