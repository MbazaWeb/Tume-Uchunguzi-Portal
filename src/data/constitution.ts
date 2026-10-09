export type Lang='sw'|'en';
export interface ConstitutionArticle{id:string;documentId:string;number:string;title:string;text:string;chapter:string;verified:boolean}
export interface ConstitutionDocument{id:string;title:string;year:number;version:string;description:string;articles:ConstitutionArticle[]}
export const documents:ConstitutionDocument[]=[
{id:'union-1977',title:'Katiba ya Jamhuri ya Muungano wa Tanzania',year:1977,version:'Toleo la maktaba',description:'Maktaba ya Katiba ya Jamhuri ya Muungano wa Tanzania. Maandishi kamili yataunganishwa kutoka kwenye dataset ya Katiba iliyotolewa.',articles:[]},
{id:'zanzibar-1984',title:'Katiba ya Zanzibar',year:1984,version:'Toleo la maktaba',description:'Maktaba ya Katiba ya Zanzibar. Maandishi kamili yataunganishwa kutoka kwenye dataset ya Katiba iliyotolewa.',articles:[]}
];
export const discussionCategories=['Historia','Mjadala wa Jumla','Tafsiri ya Kisheria','Maboresho','Haki na Wajibu','Muungano','Serikali na Taasisi','Rasilimali za Elimu'];
export const proposalTabs=['Rasimu','Sababu','Vyanzo vya Maoni','Mjadala','Kura','Mapitio ya Kisheria','Historia ya Mabadiliko','Linganisha'];
export const workflow=['Citizen Input','Moderation','Clustering','Legal Review','Committee Approval','Published'];