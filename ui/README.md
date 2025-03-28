# MCP Deployment Manager - UI

This directory contains the React frontend for the MCP Deployment Manager desktop application.

## Project Structure

- `public/`: Contains static assets and the main `index.html` file.
- `src/`: Contains the React source code.
  - `components/`: Reusable UI components.
  - `pages/`: Components representing the main sections of the application (Dashboard, Server Catalog, etc.).
  - `App.js`: Main application component, handling routing and layout.
  - `index.js`: Application entry point.

## Available Scripts

In the project directory, you can run:

### `yarn start`

Runs the app in development mode. Open [http://localhost:3000](http://localhost:3000) to view it in your browser.

The page will reload when you make changes.

### `yarn test`

Launches the test runner in interactive watch mode.

### `yarn build`

Builds the app for production to the `build` folder.

### `yarn electron:start`

Starts the React development server and then launches the Electron application.

### `yarn electron:build`

Builds the React app and packages it into a distributable Electron application.
