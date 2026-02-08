import { getNavigation } from '$lib/server/docs';

export const prerender = true;

export async function load() {
	const navigation = await getNavigation();
	return { navigation };
}
