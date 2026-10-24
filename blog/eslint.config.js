import js from '@eslint/js';
import ts from 'typescript-eslint';
import svelte from 'eslint-plugin-svelte';
import prettier from 'eslint-config-prettier';
import globals from 'globals';

/** @type {import('eslint').Linter.Config[]} */
export default [
	js.configs.recommended,
	...ts.configs.recommended,
	...svelte.configs['flat/recommended'],
	prettier,
	...svelte.configs['flat/prettier'],
	{
		languageOptions: {
			globals: {
				...globals.browser,
				...globals.node
			}
		}
	},
	{
		files: ['**/*.svelte'],
		languageOptions: {
			parserOptions: {
				parser: ts.parser
			}
		}
	},
	{
		// Generated output and checkouts, none of it source. `docs/` is the built site
		// (gitignored, rebuilt by `just build`), and `worktree/` holds linked agent
		// worktrees — each a full second copy of `src/`, so linting it reports every
		// problem twice and attributes it to the wrong tree.
		ignores: ['build/', '.svelte-kit/', 'dist/', 'docs/', 'worktree/']
	}
];
