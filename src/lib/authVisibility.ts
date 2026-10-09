import {supabase} from './supabase';
import './authVisibility.css';

if(typeof document!=='undefined'){
  let authEventReceived=false;
  const applyAuthState=(signedIn:boolean)=>{
    if(signedIn)document.documentElement.dataset.authenticated='true';
    else delete document.documentElement.dataset.authenticated;
  };
  supabase.auth.getSession().then(({data})=>{
    if(!authEventReceived)applyAuthState(Boolean(data.session?.user));
  });
  supabase.auth.onAuthStateChange((_event,session)=>{
    authEventReceived=true;
    applyAuthState(Boolean(session?.user));
  });
}