import React from 'react';
import ReactDOM from 'react-dom/client';
import {createBrowserRouter,Link} from 'react-router';
import {RouterProvider} from 'react-router/dom';
import App from './App';
import {AccountAccessPage,CommissionHomePage,InquiryInboxPage,InquiryTrackingPage} from './CommissionPortal';
import {InquiryWizard as InquirySubmissionPage} from './InquiryWizard';
import Dashboard from './Dashboard';
import RoleBasedDashboard from './RoleBasedDashboard';
import {AdminUsersPage,CommitteePage,WorkflowPage} from './StaffPages';
import {AdminDashboard,CommitteeDashboard,WorkflowDashboard} from './StaffDashboards';
import './styles.css';

function NotFoundPage(){return <section className="section"><div className="emptyState"><h1>404</h1><h2>Ukurasa haujapatikana / Page not found</h2><p>Kiungo hiki hakipo au kimebadilishwa. / This link does not exist or has changed.</p><Link className="primary linkBtn" to="/">Rudi Mwanzo / Back Home</Link></div></section>}
const router=createBrowserRouter([{path:'/',Component:App,children:[
  {index:true,Component:CommissionHomePage},
  {path:'toa-taarifa',Component:InquirySubmissionPage},
  {path:'taarifa-zangu',Component:InquiryTrackingPage},
  {path:'dashboard',Component:RoleBasedDashboard},
  {path:'admin',Component:AdminDashboard},
  {path:'admin/inquiries',Component:InquiryInboxPage},
  {path:'admin/users',Component:AdminUsersPage},
  {path:'workflow',Component:WorkflowDashboard},
  {path:'workflow/assignments',Component:WorkflowPage},
  {path:'committee',Component:CommitteeDashboard},
  {path:'committee/submissions',Component:CommitteePage},
  {path:'account',Component:AccountAccessPage},
  {path:'*',Component:NotFoundPage}
]}]);
ReactDOM.createRoot(document.getElementById('root')!).render(<React.StrictMode><RouterProvider router={router}/></React.StrictMode>);

