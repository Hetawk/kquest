import type { PageLoad } from './$types';

export const load: PageLoad = ({ params }) => ({
	shareCode: params.code
});
