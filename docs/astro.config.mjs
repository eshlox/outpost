// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const REPO = 'https://github.com/eshlox/outpost';

export default defineConfig({
  site: 'https://outpost.eshlox.net',
  integrations: [
    starlight({
      title: 'outpost',
      description:
        'One hardened Docker container per project on a remote host, driven from your terminal.',
      social: [{ icon: 'github', label: 'GitHub', href: REPO }],
      editLink: { baseUrl: `${REPO}/edit/main/docs/` },
      sidebar: [
        {
          label: 'Start here',
          items: [
            { label: 'Introduction', slug: 'index' },
            { label: 'Is this for you?', slug: 'is-this-for-you' },
            { label: 'How it compares', slug: 'comparison' },
            { label: 'Installation', slug: 'installation' },
            { label: 'Host provisioning', slug: 'guides/host-provisioning' },
            { label: 'Quickstart', slug: 'quickstart' },
          ],
        },
        {
          label: 'Concepts',
          items: [
            { label: 'Architecture', slug: 'concepts/architecture' },
            { label: 'Configuration', slug: 'concepts/configuration' },
            { label: 'Managing projects', slug: 'concepts/projects' },
            { label: 'Security model', slug: 'concepts/security' },
          ],
        },
        {
          label: 'Guides',
          items: [
            { label: 'The daily loop', slug: 'guides/daily' },
            { label: 'Running agents autonomously', slug: 'guides/agents' },
            { label: 'Git & SSH', slug: 'guides/git-and-ssh' },
            { label: 'Services (Postgres/Redis/…)', slug: 'guides/services' },
            { label: 'Tunnels', slug: 'guides/tunnels' },
            { label: 'Base image & updates', slug: 'guides/base-and-updates' },
            { label: 'Backups & migration', slug: 'guides/backups' },
            { label: 'Edit-on-laptop (Mutagen)', slug: 'guides/mutagen-sync' },
            { label: 'Mobile (Expo)', slug: 'guides/expo-mobile' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'Commands', slug: 'reference/commands' },
            { label: 'Examples', slug: 'reference/examples' },
            { label: 'Troubleshooting & FAQ', slug: 'reference/troubleshooting' },
            { label: 'Internals (why the code looks like this)', slug: 'reference/internals' },
          ],
        },
      ],
    }),
  ],
});
