import type { PageLoad } from './$types';

export const load: PageLoad = ({ params, url }) => ({
	activityId: params.id,
	editMode: url.searchParams.get('edit') === 'true'
});
