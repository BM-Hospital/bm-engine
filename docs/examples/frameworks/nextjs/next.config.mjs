/** @type {import("next").NextConfig} */
export default {
  serverExternalPackages: ["bm-render"],
  // the native platform package (@hunghg255/bm-render-<platform>) is not followed by Turbopack's file tracing
  outputFileTracingIncludes: { "/*": ["./node_modules/bm-render-*/**"] },
};
