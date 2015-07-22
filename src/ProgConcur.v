Require Import Mem.
Require Import Prog.
Require Import Word.
Require Import Hoare.
Require Import Pred.
Require Import RG.
Require Import Arith.
Require Import SepAuto.
Require Import List.

Import ListNotations.

Set Implicit Arguments.


Section STAR.

  Variable state : Type.
  Variable step : state -> state -> Prop.

  Inductive star : state -> state -> Prop :=
  | star_refl : forall s,
    star s s
  | star_step : forall s1 s2 s3,
    step s1 s2 ->
    star s2 s3 ->
    star s1 s3.

  Hint Constructors star.

  Inductive star_r : state -> state -> Prop :=
  | star_r_refl : forall s,
    star_r s s
  | star_r_step : forall s1 s2 s3,
    star_r s1 s2 ->
    step s2 s3 ->
    star_r s1 s3.

  Hint Constructors star_r.

  Lemma star_r_trans : forall s0 s1 s2,
    star_r s1 s2 ->
    star_r s0 s1 ->
    star_r s0 s2.
  Proof.
    induction 1; eauto.
  Qed.

  Lemma star_trans : forall s0 s1 s2,
    star s0 s1 ->
    star s1 s2 ->
    star s0 s2.
  Proof.
    induction 1; eauto.
  Qed.

  Theorem star_lr_eq : forall s s',
    star s s' <-> star_r s s'.
  Proof.
    intros.
    split; intros.
    induction H; eauto.
    eapply star_r_trans; eauto.
    induction H; eauto.
    eapply star_trans; eauto.
  Qed.


End STAR.

(* TODO: remove duplication *)
Hint Constructors star.
Hint Constructors star_r.

Theorem stable_star : forall AT AEQ V (p: @pred AT AEQ V) a,
  stable p a -> stable p (star a).
Proof.
  unfold stable.
  intros.
  induction H1; eauto.
Qed.

Section ExecConcurOne.

  Inductive env_outcome (T: Type) :=
  | EFailed
  | EFinished (m: @mem addr (@weq addrlen) valuset) (v: T).

  Inductive env_step_label :=
  | StepThis (m m' : @mem addr (@weq addrlen) valuset)
  | StepOther (m m' : @mem addr (@weq addrlen) valuset).

  Inductive env_exec (T: Type) : mem -> prog T -> list env_step_label -> env_outcome T -> Prop :=
  | EXStepThis : forall m m' p p' out events,
    step m p m' p' ->
    env_exec m' p' events out ->
    env_exec m p ((StepThis m m') :: events) out
  | EXFail : forall m p, (~exists m' p', step m p m' p') -> (~exists r, p = Done r) ->
    env_exec m p nil (EFailed T)
  | EXStepOther : forall m m' p out events,
    env_exec m' p events out ->
    env_exec m p ((StepOther m m') :: events) out
  | EXDone : forall m v,
    env_exec m (Done v) nil (EFinished m v).

  Definition env_corr2 (pre : forall (done : donecond nat),
                              forall (rely : @action addr (@weq addrlen) valuset),
                              forall (guarantee : @action addr (@weq addrlen) valuset),
                              @pred addr (@weq addrlen) valuset)
                       (p : prog nat) : Prop :=
    forall done rely guarantee m,
    pre done rely guarantee m ->
    (* stability of precondition under rely *)
    (stable (pre done rely guarantee) rely) /\
    forall events out,
    env_exec m p events out ->
    (* any prefix where others satisfy rely,
       we will satisfy guarantee *)
    (forall m0 m1 n, (In (StepOther m0 m1) (firstn n events) -> rely m0 m1) ->
      (In (StepThis m0 m1) (firstn n events) -> guarantee m0 m1)) /\
    ((forall m0 m1, In (StepOther m0 m1) events -> rely m0 m1) ->
     exists md vd, out = EFinished md vd /\ done vd md).

End ExecConcurOne.

Hint Constructors env_exec.


Notation "{C pre C} p" := (env_corr2 pre%pred p) (at level 0, p at level 60, format
  "'[' '{C' '//' '['   pre ']' '//' 'C}'  p ']'").

Theorem env_corr2_stable : forall pre p d r g m,
  {C pre C} p ->
  pre d r g m ->
  stable (pre d r g) r.
Proof.
  unfold env_corr2.
  intros.
  specialize (H _ _ _ _ H0).
  intuition.
Qed.

Lemma env_exec_progress :
  forall T (p : prog T) m, exists events out,
  env_exec m p events out.
Proof.
  intros T p.
  induction p; intros; eauto; case_eq (m a); intros.
  (* handle non-error cases *)
  all: try match goal with
  | [ _ : _ _ = Some ?p |- _ ] =>
    destruct p; edestruct H; repeat deex; repeat eexists; eauto
  end.
  (* handle error cases *)
  all: repeat eexists; eapply EXFail; intro; repeat deex;
  try match goal with
  | [ H : step _ _ _ _ |- _] => inversion H
  end; congruence.

  Grab Existential Variables.
  all: eauto.
Qed.

Lemma env_exec_append_event :
  forall T m (p : prog T) events m' m'' v,
  env_exec m p events (EFinished m' v) ->
  env_exec m p (events ++ [StepOther m' m'']) (EFinished m'' v).
Proof.
  intros.
  remember (EFinished m' v) as out.
  induction H; simpl; eauto.
  congruence.
  inversion Heqout; eauto.
Qed.

Example rely_just_before_done :
  forall pre p,
  {C pre C} p ->
  forall done rely guarantee m,
  pre done rely guarantee m ->
  forall events out,
  env_exec m p events out ->
  (forall m0 m1, In (StepOther m0 m1) events -> rely m0 m1) ->
  exists vd md, out = EFinished md vd /\ done vd md /\
  (forall md', rely md md' -> done vd md').
Proof.
  unfold env_corr2.
  intros.
  specialize (H _ _ _ _ H0).
  intuition.
  assert (H' := H4).
  specialize (H' _ _ H1).
  intuition.
  repeat deex.
  do 2 eexists; intuition.
  specialize (H4 (events ++ [StepOther md md']) (EFinished md' vd)).
  destruct H4.
  - eapply env_exec_append_event; eauto.
  - edestruct H6.
    intros.
    match goal with
    | [ H: In _ (_ ++ _) |- _ ] => apply in_app_or in H; destruct H;
      [| inversion H]
    end.
    apply H2; auto.
    congruence.
    contradiction.
    deex.
    congruence.
Qed.


Section ExecConcurMany.

  Inductive threadstate :=
  | TNone
  | TRunning (p : prog nat).

  Definition threadstates := forall (tid : nat), threadstate.
  Definition results := forall (tid : nat), nat.

  Definition upd_prog (ap : threadstates) (tid : nat) (p : threadstate) :=
    fun tid' => if eq_nat_dec tid' tid then p else ap tid'.

  Lemma upd_prog_eq : forall ap tid p, upd_prog ap tid p tid = p.
  Proof.
    unfold upd_prog; intros; destruct (eq_nat_dec tid tid); congruence.
  Qed.

  Lemma upd_prog_eq' : forall ap tid p tid', tid = tid' -> upd_prog ap tid p tid' = p.
  Proof.
    intros; subst; apply upd_prog_eq.
  Qed.

  Lemma upd_prog_ne : forall ap tid p tid', tid <> tid' -> upd_prog ap tid p tid' = ap tid'.
  Proof.
    unfold upd_prog; intros; destruct (eq_nat_dec tid' tid); congruence.
  Qed.

  Inductive coutcome :=
  | CFailed
  | CFinished (m : @mem addr (@weq addrlen) valuset) (rs : results).

  Inductive cexec : mem -> threadstates -> coutcome -> Prop :=
  | CStep : forall tid ts m m' (p : prog nat) p' out,
    ts tid = TRunning p ->
    step m p m' p' ->
    cexec m' (upd_prog ts tid (TRunning p')) out ->
    cexec m ts out
  | CFail : forall tid ts m (p : prog nat),
    ts tid = TRunning p ->
    (~exists m' p', step m p m' p') -> (~exists r, p = Done r) ->
    cexec m ts CFailed
  | CDone : forall ts m (rs : results),
    (forall tid, ts tid = TNone \/ ts tid = TRunning (Done (rs tid))) ->
    cexec m ts (CFinished m rs).

  Definition corr_threads (pres : forall (tid : nat),
                                  forall (done : donecond nat),
                                  forall (rely : @action addr (@weq addrlen) valuset),
                                  forall (guarantee : @action addr (@weq addrlen) valuset),
                                  @pred addr (@weq addrlen) valuset)
                          (ts : threadstates) :=
    forall dones relys guarantees m out,
    (forall tid, ts tid <> TNone ->
      (pres tid) (dones tid) (relys tid) (guarantees tid) m) ->
    cexec m ts out ->
    exists m' rs, out = CFinished m' rs /\
    (forall tid, ts tid <> TNone -> (dones tid) (rs tid) m').

End ExecConcurMany.

Ltac inv_ts :=
  match goal with
  | [ H: TRunning _ = TRunning ?p |- _ ] => inversion H; clear H; subst p
  end.

Definition pres_step (pres : forall (tid : nat),
                                  forall (done : donecond nat),
                                  forall (rely : @action addr (@weq addrlen) valuset),
                                  forall (guarantee : @action addr (@weq addrlen) valuset),
                                  @pred addr (@weq addrlen) valuset)
                      (tid0:nat) m m' :=
  fun tid d r g (mthis : @mem addr (@weq addrlen) valuset) =>
    (pres tid) d r g m /\
    if (eq_nat_dec tid0 tid) then star r m' mthis
    else (pres tid) d r g mthis.

Hint Resolve in_eq.
Hint Resolve in_cons.


Lemma ccorr2_step : forall pres tid m m' p p',
  {C pres tid C} p ->
  step m p m' p' ->
  {C (pres_step pres tid m m') tid C} p'.
Proof.
  unfold pres_step, env_corr2.
  intros.
  destruct (eq_nat_dec tid tid); [|congruence].
  assert (H' := H).
  intuition; subst;
  specialize (H _ _ _ _ H2); intuition.

  - unfold stable; intros.
    intuition.
    eapply star_trans; eauto.

  - apply star_lr_eq in H3.
    generalize dependent events.
    generalize dependent n.
    induction H3; intros.
    * eapply H7 with (events := StepThis m s :: events) (n := S n);
      eauto; intros.
      simpl in H.
      destruct H; try congruence.
      apply H4; auto.
      simpl.
      intuition.
    * apply IHstar_r with (events := StepOther s2 s3 :: events)
        (n := S n); eauto.
      all: simpl; intuition; congruence.
 - apply star_lr_eq in H3.
    generalize dependent events.
    induction H3; intros.
    * eapply H' with (events := StepThis m s :: events); eauto.
      intros.
      inversion H; [congruence|].
      eauto.
    * eapply IHstar_r; eauto.
      intros ? ? Hin; inversion Hin.
      congruence.
      eauto.
Qed.

Lemma stable_and : forall AT AEQ V P (p: @pred AT AEQ V) a,
  stable p a ->
  stable (fun m => P /\ p m) a.
Proof.
  intros.
  unfold stable; intros.
  intuition eauto.
Qed.

Lemma ccorr2_stable_step : forall pres tid tid' m m' p,
  {C pres tid C} p ->
  tid <> tid' ->
  {C (pres_step pres tid' m m') tid C} p.
Proof.
  unfold pres_step, env_corr2.
  intros.
  destruct (eq_nat_dec tid' tid); [congruence|].
  inversion H1.
  match goal with
  | [ Hpre: pres _ _ _ _ m0 |- _ ] =>
    specialize (H _ _ _ _ Hpre)
  end.
  intuition.
  apply stable_and; auto.
Qed.

Ltac compose_helper :=
  match goal with
  | [ H: context[_ =a=> _] |- _ ] =>
    (* first solve a pre goal,
       then do the <>, then eauto *)
    (* TODO: re-write this with two matches *)
    eapply H; [| | | now eauto | ]; [| | eauto |]; eauto
  end.

Ltac upd_prog_case' tid tid' :=
  destruct (eq_nat_dec tid tid');
    try rewrite upd_prog_eq' in * by auto;
    try rewrite upd_prog_ne in * by auto.

Ltac upd_prog_case :=
  match goal with
  | [ H: upd_prog _ ?tid _ ?tid' = _ |- _] => upd_prog_case' tid tid'
  end.

Theorem ccorr2_no_fail : forall pre m p d r g,
  {C pre C} p ->
  pre d r g m ->
  env_exec m p nil (@EFailed nat) ->
  False.
Proof.
  unfold env_corr2.
  intros.
  edestruct H; eauto.
  edestruct H3; eauto.
  destruct H5; eauto.
  intros; contradiction.
  repeat deex.
  congruence.
Qed.

Theorem compose :
  forall ts pres,
  (forall tid p, ts tid = TRunning p ->
   {C pres tid C} p /\
   forall tid' p' m d r g d' r' g', ts tid' = TRunning p' -> tid <> tid' ->
   (pres tid) d r g m ->
   (pres tid') d' r' g' m ->
   g =a=> r') ->
  corr_threads pres ts.
Proof.
  unfold corr_threads.
  intros.
  destruct out.

  - exfalso.
    generalize dependent pres.
    generalize dependent dones.
    generalize dependent relys.
    generalize dependent guarantees.
    remember (CFailed) as cfail.
    induction H1; simpl; intros.

    + (* thread [tid] did a legal step *)
      eapply IHcexec; clear IHcexec.
      eauto.
      instantiate (pres := pres_step pres tid m m').
      * intros.
        intuition.
        -- upd_prog_case.
          ++ edestruct H2; eauto.
             inversion H4; subst.
             eapply ccorr2_step; eauto.
          ++ eapply ccorr2_stable_step; eauto.
             edestruct H2; eauto.
        -- unfold pres_step in *.
           destruct (eq_nat_dec tid tid0);
             destruct (eq_nat_dec tid tid'); try congruence;
             try rewrite upd_prog_eq' in * by auto;
             try rewrite upd_prog_ne in * by auto;
             subst; intuition.
           ** inv_ts.
              eapply H2 with (tid' := tid') (tid := tid0); eauto.
           ** inv_ts.
              eapply H2 with (tid' := tid') (tid := tid0) (m := m); eauto.
           ** eapply H2 with (tid' := tid') (tid := tid0) (m := m); eauto.
      * unfold pres_step; intros.
      destruct (eq_nat_dec tid tid0).
      subst.
      intuition.
      apply H3; congruence.

      case_eq (ts tid0); intros.
      rewrite upd_prog_ne in * by auto; congruence.
      intuition.
      apply H3; congruence.
      assert (relys tid0 m m').
      (* need guarantee, which requires applying env_corr2 with n := 1 *)
      assert (guarantees tid m m').
      edestruct H2 with (tid := tid); eauto.
      assert (Hprogress := env_exec_progress p' m').
      repeat deex.
      eapply H6 with (n := 1) (events := StepThis m m' :: events); eauto.
      (* this should be automated away *)
      eapply H3; congruence.
      simpl; intuition congruence.
      simpl; intuition.
      assert (guarantees tid =a=> relys tid0).
      eapply H2.
      3: eauto.
      eauto.
      eauto.
      eapply H3; congruence.
      eapply H3; congruence.
      eauto.
      assert (stable (pres tid0 (dones tid0) (relys tid0) (guarantees tid0)) (relys tid0)).
      eapply env_corr2_stable; eauto.
      apply H2; eauto.
      apply H3; congruence.
      eapply H7; eauto.
      apply H3; congruence.

    + (* thread [tid] failed *)
      edestruct H2; eauto.
      eapply ccorr2_no_fail; eauto.
      apply H3; congruence.

    + congruence.

  - generalize dependent pres.
    generalize dependent dones.
    generalize dependent relys.
    generalize dependent guarantees.
    remember (CFinished m0 rs) as cout.
    induction H1; simpl; intros.

    + (* thread [tid] did a legal step *)
      edestruct IHcexec; clear IHcexec.
      eauto.
      instantiate (pres := pres_step pres tid m m').
      * intros.
        intuition.
        -- upd_prog_case.
          ++ edestruct H2; eauto.
             inversion H4; subst.
             eapply ccorr2_step; eauto.
          ++ eapply ccorr2_stable_step; eauto.
             edestruct H2; eauto.
        -- unfold pres_step in *.
           destruct (eq_nat_dec tid tid0);
             destruct (eq_nat_dec tid tid'); try congruence;
             try rewrite upd_prog_eq' in * by auto;
             try rewrite upd_prog_ne in * by auto;
             subst; intuition.
           ** inv_ts.
              eapply H2 with (tid' := tid') (tid := tid0); eauto.
           ** inv_ts.
              eapply H2 with (tid' := tid') (tid := tid0) (m := m); eauto.
           ** eapply H2 with (tid' := tid') (tid := tid0) (m := m); eauto.
      * unfold pres_step; intros.
      destruct (eq_nat_dec tid tid0).
      subst.
      intuition.
      apply H3; congruence.

      case_eq (ts tid0); intros.
      rewrite upd_prog_ne in * by auto; congruence.
      intuition.
      apply H3; congruence.
      assert (relys tid0 m m').
      (* need guarantee, which requires applying env_corr2 with n := 1 *)
      assert (guarantees tid m m').
      edestruct H2 with (tid := tid); eauto.
      assert (Hprogress := env_exec_progress p' m').
      repeat deex.
      eapply H6 with (n := 1) (events := StepThis m m' :: events); eauto.
      (* this should be automated away *)
      eapply H3; congruence.
      simpl; intuition congruence.
      simpl; intuition.
      assert (guarantees tid =a=> relys tid0).
      eapply H2.
      3: eauto.
      eauto.
      eauto.
      eapply H3; congruence.
      eapply H3; congruence.
      eauto.
      assert (stable (pres tid0 (dones tid0) (relys tid0) (guarantees tid0)) (relys tid0)).
      eapply env_corr2_stable; eauto.
      apply H2; eauto.
      apply H3; congruence.
      eapply H7; eauto.
      apply H3; congruence.

      * deex; repeat eexists; intros.
        (* TODO: automate this *)
        inversion H5; subst.
        eapply H6.
        intros.
        upd_prog_case; congruence.
    + (* thread [tid] failed *)
      edestruct H2; eauto.
      exfalso.
      eapply ccorr2_no_fail; eauto.
      apply H3; congruence.

    + do 2 eexists; intuition eauto.
      case_eq (ts tid); intros; [congruence|].
      edestruct H0; eauto.
      unfold env_corr2 in H4.
      specialize (H1 _ H2).
      specialize (H4 _ _ _ _ H1).
      intuition.
      inversion Heqcout; subst.
      assert (env_exec m0 p nil (EFinished m0 (rs tid))).
      destruct (H tid); [congruence|].
      rewrite H3 in H4.
      inversion H4.
      eauto.
      specialize (H7 _ _ H4).
      intuition.
      edestruct H9.
      intros ? ? Hin; inversion Hin.
      deex.
      congruence.
Qed.

Ltac inv_step :=
  match goal with
  | [ H: step _ _ _ _ |- _ ] => inversion H; clear H; subst
  end.

Lemma act_star_ptsto : forall AT AEQ V F a v (m1 m2: @mem AT AEQ V),
  (F * a |-> v)%pred m1 ->
  ( (F ~> F) * act_id_pred (a |->?) )%act m1 m2 ->
  (F * a |-> v)%pred m2.
Proof.
  intros.
  eapply act_star_stable_invariant_preserves; eauto.
  apply act_impl_refl.
  apply ptsto_preserves.
Qed.

Theorem write_cok : forall a vnew rx,
  {C
    fun done rely guarantee =>
    exists F v0 vrest,
    F * a |-> (v0, vrest) *
    [[ rely =a=> (F ~> F) * act_id_pred (a |->?) ]] *
    [[ act_id_any * (a |->? ~> a |->?) =a=> guarantee ]] *
    [[ {C
         fun done_rx rely_rx guarantee_rx =>
         F * a |-> (vnew, [v0] ++ vrest) *
         [[ done_rx = done ]] *
         [[ rely =a=> rely_rx ]] *
         [[ guarantee_rx =a=> guarantee ]]
       C} rx tt ]]
  C} Write a vnew rx.
Proof.
  unfold env_corr2; intros.
  destruct_lift H.
  intuition.
  (* stability *)
  - unfold stable; intros;
    destruct_lift H0.
    repeat eexists.
    repeat apply sep_star_lift_apply'; eauto.
    apply H9 in H1.
    eapply act_star_ptsto; eauto.
  (* guarantee *)
  - apply H3.
    (* induction over H0 (env_exec) *)
Admitted.

Theorem pimpl_cok : forall pre pre' (p : prog nat),
  {C pre' C} p ->
  (forall done rely guarantee, pre done rely guarantee =p=> pre' done rely guarantee) ->
  {C pre C} p.
Proof.
  unfold ccorr2; intros.
  eapply H; eauto.
  eapply H0.
  eauto.
Qed.

Definition write2 a b va vb (rx : prog nat) :=
  Write a va;;
  Write b vb;;
  rx.

Theorem parallel_composition : forall ts (dones : nat -> donecond nat) pres relys guars,
  (forall tid p, ts tid = TRunning p ->
    {C pres tid C} p) ->
  (forall tid tid', tid <> tid' ->
    guars tid' =a=> relys tid) ->
  forall m,
    (forall tid,
    (pres tid) (dones tid) (relys tid) (guars tid) m) ->
  forall out,
    cexec m ts out ->
    exists m' rs,
      out = CFinished m' rs /\
      forall tid, (dones tid) (rs tid) m'.
Proof.
  intros.
  generalize dependent H.
  induction H2; intros.
  - (* CStep *)
    admit.
  - (* CFail *)
    admit.
  - (* CDone *)
    admit.
Admitted.

Theorem write2_cok : forall a b vanew vbnew rx,
  {C
    fun done rely guarantee =>
    exists F va0 varest vb0 vbrest,
    F * a |-> (va0, varest) * b |-> (vb0, vbrest) *
    [[ forall F0 F1 va vb, rely =a=> (F0 * a |-> va * b |-> vb ~>
                                      F1 * a |-> va * b |-> vb) ]] *
    [[ forall F va va' vb vb', (F * a |-> va  * b |-> vb ~>
                                F * a |-> va' * b |-> vb') =a=> guarantee ]] *
    [[ {C
         fun done_rx rely_rx guarantee_rx =>
         exists F', F' * a |-> (vanew, [va0] ++ varest) * b |-> (vbnew, [vb0] ++ vbrest) *
         [[ done_rx = done ]] *
         [[ rely =a=> rely_rx ]] *
         [[ guarantee_rx =a=> guarantee ]]
       C} rx ]]
  C} write2 a b vanew vbnew rx.
Proof.
  unfold write2; intros.

  eapply pimpl_cok. apply write_cok.
  intros. cancel.

  eapply act_impl_trans; [ eapply H3 | ].
  (* XXX need some kind of [cancel] for actions.. *)
  admit.

  eapply act_impl_trans; [ | eapply H2 ].
  (* XXX need some kind of [cancel] for actions.. *)
  admit.

  eapply pimpl_cok. apply write_cok.
  intros; cancel.

  (* XXX hmm, the [write_cok] spec is too weak: it changes [F] in the precondition
   * with [F'] in the postcondition, and thus loses all information about blocks
   * other than the one being written to.  but really we should be using [rely].
   * how to elegantly specify this in separation logic?
   *)
  admit.

  (* XXX H5 seems backwards... *)
  admit.

  (* XXX H4 seems backwards... *)
  admit.

  eapply pimpl_cok. eauto.
  intros; cancel.

  (* XXX some other issue with losing information in [write_cok]'s [F] vs [F'].. *)
  admit.

  eapply act_impl_trans; eassumption.
  eapply act_impl_trans; eassumption.
Admitted.
