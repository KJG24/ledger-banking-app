import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// GitHub Pages project sites are served from https://<user>.github.io/<repo>/,
// not from the domain root, so asset URLs need that repo-name prefix or
// every JS/CSS request 404s. Locally (and for any host that serves from
// root) BASE_PATH is unset and this defaults back to "/".
const basePath = process.env.BASE_PATH ?? "/";

export default defineConfig({
  base: basePath,
  plugins: [react()],
  server: {
    port: 5173,
  },
});
