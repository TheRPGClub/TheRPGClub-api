# Website Themes restyle shared components with CSS only

Members will choose a Theme for the website, and Themes are meant to look nothing alike (a magazine, a Final Fantasy menu, Frutiger Aero glass). We decided every Theme restyles the same components through CSS alone: a Theme is a stylesheet that sets the colour, type and shape tokens and styles each shadcn primitive by its `data-slot` and `data-variant` attributes, and it never swaps a React component. Feature and page code may only pass layout classes (spacing, size, placement) to a primitive, and a primitive's variants name what a thing is (`tone="gotm"`, `variant="inverse"`) rather than how it looks, so every Theme can reach every surface. We rejected per-Theme component overrides because they multiply the component tree the site is being split down to size, server components cannot read a Theme from React context, and behaviour and accessibility would drift between Themes.

## Consequences

- A Theme that needs an element CSS cannot draw gets a generic, empty, decorative slot added to the shared component (for example `data-slot="ornament"`), never a fork of it.
- Themes cannot change a page's structure or behaviour, or add sound.
- The site-wide design rules keep only what every Theme must honour (contrast, focus, reduced motion, target size); each Theme's own rules live with that Theme. The Monthly Issue look is the first Theme and the default, with no special standing in the primitives.
