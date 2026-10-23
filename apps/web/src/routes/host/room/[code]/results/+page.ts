import type { PageLoad } from './$types';

export const load: PageLoad = ({ params }) => ({ code: params.code });
