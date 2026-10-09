import {createContext,useContext} from 'react';

export type AppLanguage='sw'|'en';
export const LanguageContext=createContext<{language:AppLanguage;setLanguage:(v:AppLanguage)=>void;t:<T>(sw:T,en:T)=>T}>({language:'sw',setLanguage:()=>{},t:<T>(sw:T)=>sw});
export function useLanguage(){return useContext(LanguageContext)}
