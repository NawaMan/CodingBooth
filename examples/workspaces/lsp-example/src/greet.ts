// typescript-language-server: hover `greet`, or pass a number to see the type error.
export function greet(name: string): string {
  return `Hello, ${name}!`;
}

console.log(greet("World"));
