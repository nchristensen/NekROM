c-----------------------------------------------------------------------
      subroutine rom_update_ei

      include 'SIZE'
      include 'TOTAL'
      include 'MOR'

      integer icalld
      save    icalld
      data    icalld /0/

      common /rom_update/ rom_time

      if (icalld.eq.0) then
         call opcopy(uic,vic,wic,vx,vy,vz)
         rom_time=0.
         icalld=1
      endif

      stime=dnekclock()

      ad_step = istep
      jfield=ifield
      ifield=1

      call rom_setup
      call sets_diag

      if (nio.eq.0) write (6,*) 'starting rom_step loop',ad_nsteps

      ad_step = 1
      do i=1,ad_nsteps
         call rom_step
         time=time+dt
         ad_step=ad_step+1
      enddo

      call sett_diag

      if (nio.eq.0) write (6,*) eest_diag(),ad_re,'error_estimate'

      ifield=jfield

      dtime=dnekclock()-stime
      rom_time=rom_time+dtime

      return
      end
c-----------------------------------------------------------------------
      function csig_diag(g1,g2,g3,h1,h2,op)

      include 'SIZE'

      character*3 op

      parameter (lt=lx1*ly1*lz1*lelt)

      common /scrsig/ r1(lt),r2(lt),r3(lt)
      real g1(lt),g2(lt),g3(lt),h1(lt),h2(lt)

      tolh=1.e-5
      nmxhi=1000

      call invop(r1,r2,r3,g1,g2,g3,h1,h2,tolh,nmxhi,op)

      mio=nio
      nio=-1
      csig_diag=vip(r1,r2,r3,r1,r2,r3)
      nio=mio

      return
      end
c-----------------------------------------------------------------------
      subroutine invop(r1,r2,r3,g1,g2,g3,h1,h2,tolh,nmxhi,op)

      include 'SIZE'

      parameter (lt=lx1*ly1*lz1*lelt)
      common /scrinvop/ u1(lt),u2(lt),u3(lt)

      real g1(1),g2(1),g3(1),h1(1),h2(1)
      real r1(1),r2(1),r3(1)

      character*3 op

      call opcopy(u1,u2,u3,g1,g2,g3)

      if (op.eq.'H10') then
         call exitti('H10 not yet implemented$',1)
         ! does not converge
         call ophinv(r1,r2,r3,g1,g2,g3,h1,h2,tolh,nmxhi)
      else if (op.eq.'L2 ') then
         call opbinv1(r1,r2,r3,g1,g2,g3,1.)
      else
         call exitti('did not provide supported operator$',1)
      endif

      call opcopy(g1,g2,g3,u1,u2,u3)

      return
      end
c-----------------------------------------------------------------------
      subroutine sets_diag ! set sigmas

      include 'SIZE'
      include 'MOR'
      include 'MASS'
      include 'INPUT'

      parameter (lt=lx1*ly1*lz1*lelt)

      common /scrsets/ g1(lt),g2(lt),g3(lt)

      n=lx1*ly1*lz1*nelt

      ifprojfld(1)=.false.

      do j=0,nb
         call col3(g1,ub(1,j),bm1,n)
         call col3(g2,vb(1,j),bm1,n)
         if (ldim.eq.3) call col3(g3,wb(1,j),bm1,n)
         sigb_diag(j)=csig_diag(g1,g2,g3,ones,zeros,ips)

         call axhelm(g1,ub(1,j),ones,zeros,1,1)
         call axhelm(g2,vb(1,j),ones,zeros,1,1)
         if (ldim.eq.3) call axhelm(g3,wb(1,j),ones,zeros,1,1)
         siga_diag(j)=csig_diag(g1,g2,g3,ones,zeros,ips)

         call setcnv_c(ub(1,j),vb(1,j),wb(1,j))
         do i=0,nb
            call setcnv_u(ub(1,i),vb(1,i),wb(1,i))
            call ccu(g1,g2,g3)
            sigc_diag(i,j)=csig_diag(g1,g2,g3,ones,zeros,ips)
         enddo
      enddo

      if (param(94).gt.0) ifprojfld(1)=.true.

      return
      end
c-----------------------------------------------------------------------
      subroutine sett_diag ! set thetas

      include 'SIZE'
      include 'MOR'

      call rzero(thb_diag,nb+1)
      call add2s2(thb_diag,uj(0,1),-5./6,nb+1)
      call add2s2(thb_diag,uj(0,2), 1./6,nb+1)
      call add2s2(thb_diag,uj(0,3),-1./3,nb+1)
      call add2s2(thb_diag,uj(0,4), 1./3,nb+1)
      call add2s2(thb_diag,uj(0,5),-7./6,nb+1)
      call add2s2(thb_diag,uj(0,6),11./6,nb+1)

      s=1./(ad_dt*ad_nsteps)
      call cmult(thb_diag,s,nb+1)

      s=1./ad_re
      call cmult2(tha_diag,ua,s,nb+1)

      call copy(thc_diag,u2a,(nb+1)**2)
c     call chsign(thc_diag,(nb+1)**2)

      call add2s2(thc_diag,u2j(0,0,2),-1.*rinstep,(nb+1)**2)
      call add2s2(thc_diag,u2j(0,0,5),-1.*rinstep,(nb+1)**2)
      call add2s2(thc_diag,u2j(0,0,6), 2.*rinstep,(nb+1)**2)

      return
      end
c-----------------------------------------------------------------------
      function eest(theta,sig_full,nr) ! compute error estimate

      include 'SIZE'
      include 'MOR'

      real theta(nr),sig_full(nr,nr)

      eest=0.

      do j=1,nr
      do i=1,nr
         eest=eest+sig_full(i,j)*theta(i)*theta(j)
      enddo
      enddo

      eest=sqrt(eest)

      return
      end
c-----------------------------------------------------------------------
      function eest_diag() ! compute error estimate

      include 'SIZE'
      include 'MOR'

      eest=0.

      do j=0,nb
         eest=eest+sigb_diag(j)*thb_diag(j)**2
         eest=eest+siga_diag(j)*tha_diag(j)**2
         do i=0,nb
            eest=eest+sigc_diag(i,j)*thc_diag(i,j)**2
         enddo
      enddo

      eest_diag=sqrt(eest)

      return
      end
c-----------------------------------------------------------------------
      subroutine csig_laplace(f,gg,sig_full,Nr)

      include 'SIZE'
      include 'TOTAL'
      include 'MOR'

      parameter (lt=lx1*ly1*lz1*lelt)

      real f(lt), gg(lt,0:nb)
      real rr(lt,Nr), rg(lt,Nr)
      real sig_full(Nr,Nr)
      real work(lt)

      tolh=1.e-9
      nmxhi=1000

      call copy(rg(1,1),f,lt)

      do ie=1,nelt
         do i=1,nb
            call copy(work,gg(1,i),lt)
            call emask(work,ie)
            call copy(rg(1,1+i+(ie-1)*nb),work,lt)
         enddo
      enddo
      ! compute riesz representives
c      do i=1,Nr
c         call hmholtz('ries',rr(1,i),rg(1,i),ones,zeros,tmask,tmult,2,
c     $   tolh,nmxhi,1)
c      enddo
      do i=1,Nr
         call invs(rr(1,i),rg(1,i),ones,zeros,tolh,nmxhi,'L2 ',Nr)
      enddo
      write (6,*) 'wp-2.4'

      do i=1,Nr
      do j=1,lx1*ly1*lz1*nelv
         write (6,*) i,j,rr(j,i)
      enddo
      enddo

      mio=nio
      nio=-1
      !  compute Sigma
      do j=1,Nr
         do i=1,Nr
            sig_full(i,j)=sip(rr(1,i),rr(1,j))
         enddo
      enddo
      nio=mio
      write (6,*) 'wp-2.5'

      return
      end
c-----------------------------------------------------------------------
      subroutine crhs_laplace(f,gg)

      include 'SIZE'
      include 'MOR'

      parameter (lt=lx1*ly1*lz1*lelt)

      real f(lx1,ly1,lz1,lelt)
      real gg(lx1*ly1*lz1*lelt,0:nb)

      call setf(f)
      call csga(gg,tb) ! get full g

      return
      end
c-----------------------------------------------------------------------
      subroutine sett_laplace(theta,coef,tdiff,Nr) ! set thetas

      include 'SIZE'
      include 'MOR'

      real theta(Nr)
      real coef(0:nb)
      real tmp(nb)
      real tdiff(lx1,ly1,lz1,lelt)

      theta(1) = 1.

      do i=1,nelt 
         call cfill(tmp,tdiff(1,1,1,i),nb) 
         call col2(tmp,coef(1),nb)
         call chsign(tmp,nb)
         call copy(theta(2+(i-1)*nb),tmp,nb)
      enddo

      return
      end
c-----------------------------------------------------------------------
      subroutine invs(r1,g1,h1,h2,tolh,nmxhi,op,nr)

      include 'SIZE'

      parameter (lt=lx1*ly1*lz1*lelt)
      common /scrinvop/ u1(lt),u2(lt),u3(lt)

      real g1(lt),h1(1),h2(1)
      real r1(lt)

      character*3 op

      call copy(u1,g1,lt)

      if (op.eq.'H10') then
         call exitti('H10 not yet implemented$',1)
         ! does not converge
         !call ophinv(r1,r2,r3,g1,g2,g3,h1,h2,tolh,nmxhi)
      else if (op.eq.'L2 ') then
         call binv1(r1,g1,1.) 
      else
         call exitti('did not provide supported operator$',1)
      endif

      call copy(g1,u1,lt)

      return
      end
c-----------------------------------------------------------------------
