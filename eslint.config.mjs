import { defineConfig } from 'eslint/config'
import typescriptEslint from 'typescript-eslint'
import eslintPluginRequireJsExtension from 'eslint-plugin-require-js-extension'
import eslintPluginPrettierRecommended from 'eslint-plugin-prettier/recommended'
import importPlugin from 'eslint-plugin-import'

import prettierConfig from './.prettierrc.js'

export default defineConfig([
  // Global settings
  eslintPluginPrettierRecommended,
  {
    ignores: ['/out'],
  },

  // eslint config
  {
    files: ['eslint.config.js'],
    rules: {
      'prettier/prettier': [
        'error',
        {
          ...prettierConfig,
        },
      ],
    },
  },

  // Settings for Roblox TS source files
  {
    basePath: 'src',
    files: ['**/*.{ts,tsx,js,jsx}'],
    languageOptions: {
      parser: typescriptEslint.parser,
      parserOptions: {
        jsx: true,
        useJSXTextNode: true,
        ecmaVersion: 2018,
        sourceType: 'module',
        project: './tsconfig.json',
      },
    },
    plugins: {
      '@typescript-eslint': typescriptEslint.plugin,
      'require-js-extension': eslintPluginRequireJsExtension,
      import: importPlugin,
    },
    rules: {
      'prettier/prettier': [
        'error',
        {
          ...prettierConfig,
        },
      ],
      'require-js-extension/require-js-extension': 'error',
      '@typescript-eslint/consistent-type-imports': 2,
      '@typescript-eslint/no-explicit-any': 0,
      '@typescript-eslint/no-namespace': 0,
      '@typescript-eslint/no-var-requires': 0,
      '@typescript-eslint/no-unused-vars': 1,
      'no-useless-catch': 1,
      'no-async-promise-executor': 0,
      'react/jsx-uses-react': 0,
      'import/order': [
        'error',
        {
          groups: ['builtin', 'external', 'parent', 'sibling', 'index'],
          'newlines-between': 'always',
        },
      ],
      'prefer-const': 2,
      'no-var': 2,
      'no-const-assign': 1,
      'no-this-before-super': 1,
      'no-unreachable': 2,
      'no-unneeded-ternary': 2,
      'import/no-anonymous-default-export': 0,
      'no-debugger': 1,
      'no-console': 0,
      'constructor-super': 1,
      'valid-typeof': 1,
      'arrow-body-style': ['error', 'always'],
    },
  },
])
