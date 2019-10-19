c-----------------------------------------------------------------------
      subroutine bdfext_step

      include 'SIZE'
      include 'TOTAL'
      include 'MOR'

      common /scrbdfext/ rhs(0:lb,2),rhstmp(0:lb)

      ulast_time = dnekclock()

      n=lx1*ly1*lz1*nelt

      icount = min(max(1,ad_step),3)

      rhs(0,1)=1.
      rhs(0,2)=1.

c     if (icount.le.2) then
      if (.false.) then
         if (ifrom(1)) call setr_v(rhs(1,1),icount)
         if (ifrom(2)) call setr_t(rhs(1,2),icount)
         call rk4_setup
         call copy(urki(1),u(1),nb)
         if (ifrom(2)) call copy(urki(nb+1),ut(1),nb)
         nrk=nb
         if (ifrom(2)) nrk=nb*2

         call rk_step(urko,rtmp1,urki,time,ad_dt,grk,rtmp2,nrk)

         if (ifrom(1)) then
            call copy(rhs(1,1),urko,nb)
            call shift3(u,rhs,nb+1)
         endif
         if (ifrom(2)) then
            call copy(rhs(1,2),urko(nb+1),nb)
            call shift3(ut,rhs(0,2),nb+1)
         endif
         return
      endif

      if (ifrom(2)) then
         if (ad_step.le.3) then
            ttime=dnekclock()
            call seth(hlm(1,2),at,bt,1./ad_pe)
            if (ad_step.eq.3)
     $         call dump_serial(hlm(1,2),nb*nb,'ops/ht ',nid)
            call copy(hinv(1,2),hlm(1,2),nb*nb)
            call invmat(hinv(1,2),rtmp1,itmp1,itmp2,nb)
            lu_time=lu_time+dnekclock()-ttime
         endif

         call setr_t(rhstmp,icount)

         ttime=dnekclock()
         if (isolve.eq.0) then
            call mxm(hinv(1,2),nb,rhstmp,nb,rhs(1,2),1)
         else
            call mxm(ut,nb+1,ad_alpha(1,icount),icount,rhstmp,1)
            call constrained_POD(rhs(0,2),rhstmp(1),hlm(1,2),hinv(1,2),
     $                           tmax,tmin,tdis,
     $                           tbarr0,tbarrseq,tcopt_count)
         endif
         tsolve_time=tsolve_time+dnekclock()-ttime
      endif

      if (ifrom(1)) then
         if (ad_step.le.3) then
            ttime=dnekclock()
            call seth(hlm,au,bu,1./ad_re)
            if (ad_step.eq.3) call dump_serial(hlm,nb*nb,'ops/hu ',nid)
            call copy(hinv,hlm,nb*nb)
            call copy(invhelmu,hinv,nb*nb)
            call dgetrf(nb,nb,invhelmu,nb,ipiv,info)
            call invmat(hinv,rtmp1,itmp1,itmp2,nb)
            lu_time=lu_time+dnekclock()-ttime
         endif

         call setr_v(rhstmp,icount)

         ttime=dnekclock()
         if (isolve.eq.0) then
            call mxm(hinv,nb,rhstmp,nb,rhs(1,1),1)
         else
            call mxm(ut,nb+1,ad_alpha(1,icount),icount,rhstmp,1)
            call constrained_POD(rhs(0,1),rhstmp(1),hlm,invhelmu,
     $         umax,umin,udis,ubarr0,ubarrseq,ucopt_count)
         endif
         solve_time=solve_time+dnekclock()-ttime
      endif

      if (ifrom(2)) call shift3(ut,rhs(0,2),nb+1)
      if (ifrom(1)) call shift3(u,rhs,nb+1)

      ustep_time=ustep_time+dnekclock()-ulast_time

      return
      end
c-----------------------------------------------------------------------
      subroutine post

      include 'SIZE'
      include 'TOTAL'
      include 'MOR'
      include 'AVG'

      parameter (lt=lx1*ly1*lz1*lelt)
      common /scrrstep/ t1(lt),t2(lt),t3(lt),work(lt)
      common /nekmpi/ nidd,npp,nekcomm,nekgroup,nekreal

      save icalld
      data icalld /0/

      real vort(lt)

      if (icalld.eq.0) then
         post_time=0.
         icalld=1
      endif

      call nekgsync
      tttime=dnekclock()

      if (ifrom(1)) then
         call setuavg(ua,u2a,u)
         call setuj(uj,u2j,u)
      endif

      if (ifrom(2)) then
         call settavg(uta,uuta,utua,ut2a,u,ut)
         call settj(utj,uutj,utuj,uj,ut)
      endif

      if (mod(ad_step,ad_qstep).eq.0) then
         if (ifctke) call ctke
         if (ifcdrag) call cdrag
         call cnuss
c        call cubar
      endif

      if (mod(ad_step,ad_iostep).eq.0) then
         if (nio.eq.0) then
            if (ifrom(1)) then
               do j=1,nb
                  write(6,*) j,time,u(j),'romu'
               enddo
            endif
            if (ifrom(2)) then
               do j=1,nb
                  write(6,*) j,time,ut(j),'romt'
               enddo
            endif
         endif

         if (rmode.ne.'ON ') then
            idump=ad_step/ad_iostep
            call reconv(vx,vy,vz,u)
            call opcopy(t1,t2,t3,vx,vy,vz)

            if (ifrom(2)) then
               call recont(vort,ut)
            else
               call comp_vort3(vort,work1,work2,t1,t2,t3)
            endif

            ifto = .true. ! turn on temp in fld file
            call outpost(vx,vy,vz,pavg,vort,'rom')
         endif
      endif

      if (ad_step.eq.ad_nsteps) then
         if (nio.eq.0) then
            if (ifrom(1)) then
               do j=1,nb
                  write (6,*) j,num_galu(j)/ad_nsteps,'num_galu'
               enddo
               write (6,*) anum_galu/ad_nsteps,'anum_galu'
            endif
            if (ifrom(2)) then
               do j=1,nb
                  write(6,*)j,num_galt(j)/ad_nsteps,'num_galt'
               enddo
               write(6,*)anum_galt/ad_nsteps,'anum_galt'
            endif
         endif
      endif

      call nekgsync
      postu_time=postu_time+dnekclock()-tttime

      return
      end
c-----------------------------------------------------------------------
      subroutine compute_BDF_coef(ad_alpha,ad_beta)

      real ad_alpha(3,3), ad_beta(4,3)

      call rzero(ad_alpha,3*3)
      call rzero(ad_beta,3*4)

      ad_beta(1,1) = 1.
      ad_beta(2,1) = -1.

      ad_beta(1,2) = 1.5
      ad_beta(2,2) = -2
      ad_beta(3,2) = 0.5

      ad_beta(1,3) = 11./6
      ad_beta(2,3) = -3
      ad_beta(3,3) = 1.5
      ad_beta(4,3) = -1./3.

      ad_alpha(1,1)=1

      ad_alpha(1,2)=2
      ad_alpha(2,2)=-1

      ad_alpha(1,3)=3
      ad_alpha(2,3)=-3
      ad_alpha(3,3)=1

      return
      end
c-----------------------------------------------------------------------
      subroutine evalc(cu,cm,cl,uu)

      include 'SIZE'
      include 'TOTAL'
      include 'MOR'

      real cu(nb)
      real uu(0:nb)
      real ucft(0:nb)
      real cl(ic1:ic2,jc1:jc2,kc1:kc2)
      real cm(ic1:ic2,jc1:jc2)
      real bcu(1:ltr)
      real cuu(1:ltr)

      common /scrc/ work(max(lub,ltb))

      integer icalld
      save    icalld
      data    icalld /0/

      if (icalld.eq.0) then
         evalc_time=0.
         icalld=1
      endif

      stime=dnekclock()

      if (ifcintp) then
         call mxm(cintp,n,uu,n+1,cu,1)
      else if (rmode.eq.'CP ') then
         call rzero(cu,nb)
         do kk=1,ltr
            bcu(kk) = vlsc2(uu,cub(1+(kk-1)*(lub+1)),nb+1)
            cuu(kk) = vlsc2(u,cuc(1+(kk-1)*(lub+1)),nb+1)
         enddo
         do kk=1,ltr
            do i=1,nb
               cu(i)=cu(i)+cp_w(kk)*cua(i+(kk-1)*(lub))*bcu(kk)*cuu(kk)
            enddo
         enddo

         ! debug checking
c        do kk=1,ltr
c           do k=1,nb+1
c           do j=1,nb+1
c           do i=1,nb
c              cu(i)=cu(i)+cp_w(kk)*cua(i+(kk-1)*(lub))
c    $         *cub(j+(kk-1)*(lub+1))*uu(j-1)
c    $         *cuc(k+(kk-1)*(lub+1))*u(k-1)
c           enddo
c           enddo
c           enddo
c        enddo
      else
         call rzero(cu,nb)
         if (ncloc.ne.0) then
            if ((kc2-kc1).lt.64.and.(jc2-jc1).lt.64) then
               call mxm(cl,(ic2-ic1+1)*(jc2-jc1+1),
     $                  u(kc1),(kc2-kc1+1),cm,1)
               call mxm(cm,(ic2-ic1+1),uu(jc1),(jc2-jc1+1),cu(ic1),1)
            else
               if (rfilter.eq.'STD'.or.rfilter.eq.'EF ') then
                  do k=kc1,kc2
                  do j=jc1,jc2
                  do i=ic1,ic2
                     cu(i)=cu(i)+cl(i,j,k)*uu(j)*u(k)
                  enddo
                  enddo
                  enddo
               else if (rfilter.eq.'LER') then
                  call copy(ucft,u,nb+1)

                  if (rbf.lt.0) then
                     call pod_df(ucft(1))
                  else if (rbf.gt.0) then
                     call pod_proj(ucft(1),rbf)
                  endif

                  do k=kc1,kc2
                  do j=jc1,jc2
                  do i=ic1,ic2
                     cu(i)=cu(i)+cl(i,j,k)*uu(j)*ucft(k)
                  enddo
                  enddo
                  enddo
               endif
            endif
         endif
         call gop(cu,work,'+  ',nb)
      endif

      call nekgsync

      evalc_time=evalc_time+dnekclock()-stime

      return
      end
c-----------------------------------------------------------------------
      subroutine setcintp
      call exitti('called deprecated subroutine setcintp$',1)
      return
      end
c-----------------------------------------------------------------------
      subroutine setr_t(rhs,icount)

      include 'SIZE'
      include 'MOR'

      common /scrrhs/ tmp(0:lb),tmp2(0:lb)

      real rhs(nb)

      call mxm(ut,nb+1,ad_beta(2,icount),3,tmp,1)
      call mxm(bt,nb,tmp(1),nb,rhs,1)

      call cmult(rhs,-1.0/ad_dt,nb)

      s=-1.0/ad_pe

      do i=1,nb
         rhs(i)=rhs(i)+s*at0(1+i)
      enddo

      call evalc(tmp(1),ctmp,ctl,ut)
c     call add2(tmp(1),st0(1),nb)

      call shift3(ctr,tmp(1),nb)

      call mxm(ctr,nb,ad_alpha(1,icount),3,tmp(1),1)

      call sub2(rhs,tmp(1),nb)

      if (ifsource) then
         call add2(rhs,rq,nb)
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine setr_v(rhs,icount)

      include 'SIZE'
      include 'MOR'

      common /scrrhs/ tmp1(0:lb),tmp2(0:lb)

      real rhs(nb)

      call mxm(u,nb+1,ad_beta(2,icount),3,tmp1,1)
      call mxm(bu,nb,tmp1(1),nb,rhs,1)

      call cmult(rhs,-1.0/ad_dt,nb)

      s=-1.0/ad_re

      do i=1,nb
         rhs(i)=rhs(i)+s*au0(1+i)
      enddo

      call evalc(tmp1(1),ctmp,cul,u)
      call chsign(tmp1(1),nb)

      if (ifbuoy) then
         call mxm(but0,nb+1,ut,nb+1,tmp2(0),1)
         call add2s2(tmp1(1),tmp2(1),ad_ra,nb)
      else if (ifforce) then
         call add2(tmp1(1),rg(1),nb)
      endif

      call shift3(fu,tmp1(1),nb)

      call mxm(fu,nb,ad_alpha(1,icount),3,tmp1(1),1)

      call add2(rhs,tmp1(1),nb)

      ! artificial viscosity

      if (ifavisc) then
c        call mxm(au0,nb+1,u,nb+1,tmp1,1)
         do i=1,nb
            tmp1(i)=au(i+nb*(i-1))*u(i)
         enddo

         a=5.
         s=3.
         pad=.05

         s=-s/ad_re

         call cmult(tmp1,s,nb+1)

         call rzero(tmp2,nb+1)

         eps=1.e-2

         do i=1,nb
            um=(umax(i)+umin(i))*.5
            ud=(umax(i)-umin(i))*.5*(1.+pad)
            d=(u(i)-um)/ud
c           tmp2(i)=(cosh(d*acosh(2.))-1.)**a
            if (u(i).gt.umax(i)) then
               d=(u(i)/umax(i)-1.)/(1+pad)
c              tmp2(i)=d*d
c              tmp2(i)=d
               tmp2(i)=exp(d)-1.
c              tmp2(i)=exp(d*d)-1.
c              tmp2(i)=log(d)
            endif
            if (u(i).lt.umin(i)) then
               d=(u(i)/umin(i)-1.)/(1+pad)
c              tmp2(i)=d*d
c              tmp2(i)=d
               tmp2(i)=exp(d)-1.
c              tmp2(i)=exp(d*d)-1.
c              tmp2(i)=log(d)
            endif
         enddo

         call addcol3(rhs,tmp1(1),tmp2(1),nb)
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine setuavg(s1,s2,t1)

      include 'SIZE'
      include 'MOR'

      real s1(0:nb),s2(0:nb,0:nb),t1(0:nb)

      if (ad_step.eq.navg_step) then
         call rzero(s1,nb+1)
         call rzero(s2,(nb+1)**2)
      endif

      call add2(s1,t1,nb+1)

      do j=0,nb
      do i=0,nb
         s2(i,j)=s2(i,j)+t1(i)*t1(j)
      enddo
      enddo

      if (ad_step.eq.ad_nsteps) then
         s=1./real(ad_nsteps-(navg_step-1))
         call cmult(s1,s,nb+1)
         call cmult(s2,s,(nb+1)**2)
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine settavg(s1,s2,s3,s4,t1,t2)

      include 'SIZE'
      include 'MOR'

      real s1(0:nb),s2(0:nb,0:nb),s3(0:nb,0:nb),s4(0:nb,0:nb)
      real t1(0:nb),t2(0:nb)


      if (ad_step.eq.navg_step) then
         call rzero(s1,nb+1)
         call rzero(s2,(nb+1)**2)
         call rzero(s3,(nb+1)**2)
         call rzero(s4,(nb+1)**2)
      endif

      call add2(s1,ut,nb+1)

      do j=0,nb
      do i=0,nb
         s2(i,j)=s2(i,j)+t1(i)*t2(j)
         s2(i,j)=s3(i,j)+t1(j)*t2(i)
         s2(i,j)=s4(i,j)+t2(j)*t2(i)
      enddo
      enddo

      if (ad_step.eq.ad_nsteps) then
         s=1./real(ad_nsteps-navg_step+1)
         call cmult(s1,s,nb+1)
         call cmult(s2,s,(nb+1)**2)
         call cmult(s3,s,(nb+1)**2)
         call cmult(s4,s,(nb+1)**2)
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine setuj(s1,s2,t1)

      include 'SIZE'
      include 'MOR'

      real s1(0:nb,6),s2(0:nb,0:nb,6),t1(0:nb,3)

      if (ad_step.eq.(navg_step+1)) then
         call copy(s1(0,1),t1(0,3),nb+1)
         call copy(s1(0,2),t1(0,2),nb+1)
         call copy(s1(0,3),t1(0,1),nb+1)
      endif
      if (ad_step.eq.ad_nsteps) then
         call copy(s1(0,4),t1(0,3),nb+1)
         call copy(s1(0,5),t1(0,2),nb+1)
         call copy(s1(0,6),t1(0,1),nb+1)
         do k=1,6
            call mxm(s1(0,k),nb+1,s1(0,k),1,s2(0,0,k),nb+1)
         enddo
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine settj(s1,s2,s3,t1,t2)

      include 'SIZE'
      include 'MOR'

      ! s1=utj,s2=uutj,s3=utuj,t1=uj,t2=ut

      real s1(0:nb,6),s2(0:nb,0:nb,6),s3(0:nb,0:nb,6)
      real t1(0:nb,6),t2(0:nb,3)

      if (ad_step.eq.(navg_step+1)) then
         call copy(s1(0,1),t2(0,3),nb+1)
         call copy(s1(0,2),t2(0,2),nb+1)
         call copy(s1(0,3),t2(0,1),nb+1)
      endif

      if (ad_step.eq.ad_nsteps) then
         call copy(s1(0,4),t2(0,3),nb+1)
         call copy(s1(0,5),t2(0,2),nb+1)
         call copy(s1(0,6),t2(0,1),nb+1)

         do k=1,6
         do j=0,nb
         do i=0,nb
            s2(i,j,k)=t1(i,k)*s1(j,k)
            s3(i,j,k)=t1(j,k)*s1(i,k)
         enddo
         enddo
         enddo
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine seth(flu,a,b,ad_diff)

      include 'SIZE'
      include 'MOR'

      real flu(nb,nb),a(nb,nb),b(nb,nb)

      if (ad_step.le.3) then
         call cmult2(flu,b,ad_beta(1,ad_step)/ad_dt,nb*nb)
         call add2s2(flu,a,ad_diff,nb*nb)
      endif
         
      return
      end
c-----------------------------------------------------------------------
      subroutine hybrid_advance(rhs,uu,helm,invhelm,amax,amin,
     $                          adis,bpar,bstep,copt_count) 

      include 'SIZE'
      include 'TOTAL'
      include 'MOR'  

      real helm(nb,nb),invhelm(nb,nb)
      real uu(nb),rhs(0:nb),rhstmp(0:nb)
      real amax(nb),amin(nb),adis(nb)
      real bpar
      integer bstep,chekbc,copt_count

      chekbc=0

      call copy(rhstmp,rhs,nb+1)
      call dgetrs('N',nb,1,invhelm,lub,ipiv,rhstmp(1),nb,info)

      do ii=1,nb
         if ((rhstmp(ii)-amax(ii)).ge.box_tol) then
            chekbc = 1
         elseif ((amin(ii)-rhstmp(ii)).ge.box_tol) then
            chekbc = 1
         endif
      enddo

      if (chekbc.eq.1) then
         copt_count = copt_count + 1
         call BFGS(rhs(1),uu,helm,invhelm,amax,amin,adis,
     $   bpar,bstep)
      else
         call copy(rhs,rhstmp,nb+1)
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine constrained_POD(rhs,uu,helm,invhelm,amax,amin,
     $                          adis,bpar,bstep,copt_count) 

      include 'SIZE'
      include 'TOTAL'
      include 'MOR'  

      real helm(nb,nb),invhelm(nb,nb)
      real uu(nb),rhs(0:nb),rhstmp(0:nb)
      real amax(nb),amin(nb),adis(nb)
      real bpar
      integer bstep,chekbc,copt_count

      if (isolve.eq.1) then 

         ! constrained solve with inverse update
         call BFGS_new(rhs(1),uu(1),helm,invhelm,amax,amin,adis,
     $   bpar,bstep)

      else if (isolve.eq.2) then 
                                 
         ! constrained solve with inverse update
         ! and mix with standard solver
         call copy(rhstmp,rhs,nb+1)
         call dgetrs('N',nb,1,invhelm,nb,ipiv,rhstmp(1),nb,info)

         do ii=1,nb
            if ((rhstmp(ii)-amax(ii)).ge.box_tol) then
               chekbc = 1
            elseif ((amin(ii)-rhstmp(ii)).ge.box_tol) then
               chekbc = 1
            endif
         enddo

         if (chekbc.eq.1) then
            copt_count = copt_count + 1
            call BFGS_new(rhs(1),uu(1),helm,invhelm,amax,amin,adis,
     $      bpar,bstep)
         else
            call copy(rhs,rhstmp,nb+1)
         endif

      else if (isolve.eq.3) then 

         ! constrained solve with Hessian update
         call BFGS(rhs(1),uu(1),helm,invhelm,amax,amin,adis,
     $   bpar,bstep)

      else if (isolve.eq.4) then 

         ! constrained solve with Hessian update
         ! and mix with standard solver
         call hybrid_advance(rhs,uu(1),helm,invhelm,amax,amin,
     $                       adis,bpar,bstep,copt_count)

      else if (isolve.eq.5) then 

         ! constrained solve with Hessian update
         call BFGS(rhs(1),uu(1),helm,invhelm,amax,amin,adis,
     $   bpar,bstep)

      else   
         call exitti('incorrect isolve specified...$',isolve)
      endif

      return
      end
c-----------------------------------------------------------------------
      subroutine evalc2(cu,cm,cl,uu,tt)

      include 'SIZE'
      include 'TOTAL'
      include 'MOR'

      real cu(nb)
      real uu(0:nb)
      real tt(0:nb)
      real ucft(0:nb)
      real cl(ic1:ic2,jc1:jc2,kc1:kc2)
      real cm(ic1:ic2,jc1:jc2)

      common /scrc/ work(max(lub,ltb))

      integer icalld
      save    icalld
      data    icalld /0/

      if (icalld.eq.0) then
         evalc_time=0.
         icalld=1
      endif

      stime=dnekclock()

      call rzero(cu,nb)
      if (ncloc.ne.0) then
         do k=kc1,kc2
         do j=jc1,jc2
         do i=ic1,ic2
            cu(i)=cu(i)+cl(i,j,k)*tt(j)*uu(k)
         enddo
         enddo
         enddo
         call gop(cu,work,'+  ',nb)
      endif

      call nekgsync

      evalc_time=evalc_time+dnekclock()-stime

      return
      end
c-----------------------------------------------------------------------
      subroutine evf(tt,uu,ff)

      include 'SIZE'
      include 'MOR'

      common /scrrhs/ rhs(0:lb),tmp2(0:lb),tmp3(0:lb)
      common /invevf/ buinv(lb*lb),btinv(lb*lb)
      common /screvf/ t1(0:lb),t2(0:lb),t3(0:lb),t4(0:lb)

      real uu(1),ff(1)

      call copy(t1(1),uu(1),nb)
      t1(0)=1.

      if (ifrom(1)) then
         call mxm(au0,nb+1,t1,nb+1,t2,1)

         s=-1.0/ad_re
         call cmult(t2(1),s,nb)

         call evalc2(t3(1),ctmp,cul,t1,t1)
         call sub2(t2(1),t3(1),nb)

         if (ifbuoy) then
            call copy(t3(1),uu(nb+1),nb)
            t3(0)=1.
            call mxm(but0,nb+1,t3,nb+1,t4,1)
            call add2s2(t2(1),t4(1),ad_ra,nb)
         else if (ifforce) then
            call add2(t2(1),rg(1),nb)
         endif

         call mxm(buinv,nb,t2(1),nb,ff,1)
      endif

      if (ifrom(2)) then
         call copy(t4(1),uu(nb+1),nb)
         t4(0)=1.

         call mxm(at0,nb+1,t4,nb+1,t2,1)

         s=-1.0/ad_pe
         call cmult(t2(1),s,nb)

         call evalc2(t3(1),ctmp,ctl,t1,t4)
         call sub2(t2(1),t3(1),nb)

         call mxm(btinv,nb,t2(1),nb,ff(nb+1),1)
      endif

      return
      end
c-----------------------------------------------------------------------
