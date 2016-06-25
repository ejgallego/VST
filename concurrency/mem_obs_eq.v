Require Import compcert.lib.Axioms.
Require Import concurrency.sepcomp. Import SepComp.
Require Import sepcomp.semantics_lemmas.

Require Import concurrency.pos.

Require Import compcert.lib.Coqlib.
Require Import Coq.Program.Program.
From mathcomp.ssreflect Require Import ssreflect ssrbool ssrnat ssrfun eqtype seq fintype finfun.
Set Implicit Arguments.

(*NOTE: because of redefinition of [val], these imports must appear 
  after Ssreflect eqtype.*)
Require Import compcert.common.AST.
Require Import compcert.common.Values. (*for val*)
Require Import compcert.common.Globalenvs. 
Require Import compcert.common.Memory.
Require Import compcert.common.Events.
Require Import compcert.lib.Integers.

Require Import Coq.ZArith.ZArith.

Require Import concurrency.threads_lemmas.
Require Import concurrency.permissions.
Require Import concurrency.dry_context.

Global Notation "a # b" := (Maps.PMap.get b a) (at level 1).

Module Renamings.
Definition memren := block -> option block.

Definition ren_incr f1 f2 :=
forall (b b' : block),
  f1 b = Some b' -> f2 b = Some b'.

Definition ren_separated (f f' : memren) m1 m2 :=
forall (b1 b2 : block),
f b1 = None ->
f' b1 = Some b2 ->
~ Mem.valid_block m1 b1 /\ ~ Mem.valid_block m2 b2.

Definition ren_domain_incr (f1 f2: memren) :=
  forall b,
    f1 b -> f2 b.

(** Defining the domain of a renaming with respect to a memory*)
Definition domain_memren (f: memren) m :=
  forall b, Mem.valid_block m b <-> isSome (f b).

Lemma restrPermMap_domain:
  forall f m p (Hlt: permMapLt p (getMaxPerm m)),
    domain_memren f m <-> domain_memren f (restrPermMap Hlt).
Proof.
  intros.
  unfold domain_memren.
  split; intros; specialize (H b);
  erewrite restrPermMap_valid in *;
    by auto.
Qed.

Lemma domain_memren_incr:
  forall f f' f'' m,
    domain_memren f' m ->
    domain_memren f'' m ->
    ren_domain_incr f f' <-> ren_domain_incr f f''.
Proof.
  intros.
  unfold domain_memren in *;
  split; intros Hincr b Hf;
  apply Hincr in Hf;
  destruct (H b), (H0 b);
    by eauto.
Qed.

Lemma ren_incr_domain_incr:
  forall f f',
    ren_incr f f' ->
    ren_domain_incr f f'.
Proof.
  intros f f' Hincr b Hf.
  destruct (f b) as [b'|] eqn:Hfb; try by exfalso.
  specialize (Hincr b b' Hfb);
    by rewrite Hincr.
Qed.

Lemma ren_domain_incr_refl:
  forall f,
    ren_domain_incr f f.
Proof.
  intros.
  unfold ren_domain_incr;
    by auto.
Qed.

Lemma ren_domain_incr_trans:
  forall f f' f'',
    ren_domain_incr f f' ->
    ren_domain_incr f' f'' ->
    ren_domain_incr f f''.
Proof.
  intros.
  unfold ren_domain_incr;
    by auto.
Qed.

Lemma ren_incr_trans:
  forall f f' f'',
    ren_incr f f' ->
    ren_incr f' f'' ->
    ren_incr f f''.
Proof.
  intros.
  unfold ren_incr;
    by auto.
Qed.

Lemma ren_incr_refl:
  forall f,
    ren_incr f f.
Proof.
  unfold ren_incr; auto.
Qed.

Lemma ren_separated_refl:
  forall f m m',
    ren_separated f f m m'.
Proof.
  unfold ren_separated.
    by congruence.
Qed.

 (** ** Results about id injections*)
  Definition id_ren m :=
    fun b => if is_left (valid_block_dec m b) then Some b else None.

  Hint Unfold id_ren.

  Lemma id_ren_correct:
    forall m (b1 b2 : block), (id_ren m) b1 = Some b2 -> b1 = b2.
  Proof.
    intros. unfold id_ren in *.
    destruct (valid_block_dec m b1); simpl in *;
      by inversion H.
  Qed.

  Lemma id_ren_domain:
    forall m, domain_memren (id_ren m) m.
  Proof.
    unfold id_ren, domain_memren.
    intros.
    destruct (valid_block_dec m b); simpl;
    split; intuition.
  Qed.

  Lemma id_ren_validblock:
    forall m b
      (Hvalid: Mem.valid_block m b),
      id_ren m b = Some b.
  Proof.
    intros.
    eapply id_ren_domain in Hvalid.
    destruct (id_ren m b) eqn:Hid.
    apply id_ren_correct in Hid;
      by subst.
      by exfalso.
  Qed.

  Lemma id_ren_invalidblock:
    forall m b
      (Hinvalid: ~ Mem.valid_block m b),
      id_ren m b = None.
  Proof.
    intros.
    assert (Hnot:= iffLRn (id_ren_domain m b) Hinvalid).
    destruct (id_ren m b) eqn:Hid;
      first by exfalso.
      by reflexivity.
  Qed.

  Lemma is_id_ren :
    forall f m
      (Hdomain: domain_memren f m)
      (Hf_id: forall b1 b2, f b1 = Some b2 -> b1 = b2),
      f = id_ren m.
  Proof.
    intros. extensionality b.
    assert (Hdomain_id := id_ren_domain m).
    destruct (f b) eqn:Hf, (id_ren m b) eqn:Hid;
      try (assert (H:= id_ren_correct _ _ Hid));
      try (specialize (Hf_id b _ Hf));
      subst; auto.
    assert (Hid': ~ id_ren m b0)
      by (rewrite Hid; auto).
    assert (Hf': f b0)
      by (rewrite Hf; auto).
    apply (proj2 (Hdomain b0)) in Hf'.
    apply (iffRLn (Hdomain_id b0)) in Hid';
      by exfalso.
    assert (Hid': id_ren m b0)
      by (rewrite Hid; auto).
    assert (Hf': ~ f b0)
      by (rewrite Hf; auto).
    apply (proj2 (Hdomain_id b0)) in Hid'.
    apply (iffRLn (Hdomain b0)) in Hf';
      by exfalso.
  Qed.

  Hint Immediate ren_incr_refl ren_separated_refl : renamings.
  
End Renamings.

Module MemoryWD.

  Import Renamings.
(** Valid memories are the ones that do not contain any dangling pointers*)
Definition valid_mem m :=
  forall b,
    Mem.valid_block m b ->
    forall ofs mv,
      Maps.ZMap.get ofs (Mem.mem_contents m) # b = mv ->
      match mv with
      | Fragment v q n =>
        mem_wd.val_valid v m
      | _ => True
      end.

Definition valid_val (f: memren) (v : val) : Prop :=
  match v with
  | Vptr b _ =>
    exists b', f b = Some b'
  | _ => True
  end.

Inductive valid_val_list (f: memren) : seq val -> Prop :=
  | vs_nil: valid_val_list f [::]
  | vs_cons: forall v vs,
      valid_val f v ->
      valid_val_list f vs ->
      valid_val_list f (v :: vs).

Definition valid_memval (f: memren) (mv : memval) : Prop :=
  match mv with
  | Fragment v _ _ =>
    valid_val f v
  | _ => True
  end.

Lemma wd_val_valid:
  forall v m f
    (Hdomain: domain_memren f m),
    mem_wd.val_valid v m <-> valid_val f v.
Proof.
  intros.
  unfold mem_wd.val_valid, valid_val.
  destruct v; try tauto.
  split.
  intro H.
  apply Hdomain in H.
  destruct (f b) as [b0|];
    by [exists b0; eauto | intuition].
  intros (b' & H).
  assert (H': f b)
    by (rewrite H; auto);
    by apply Hdomain in H'.
Qed.
  
Lemma valid_val_incr:
  forall f f' v
    (Hvalid: valid_val f v)
    (Hincr: ren_domain_incr f f'),
    valid_val f' v.
Proof.
  intros.
  unfold valid_val in *.
  destruct v; auto.
  destruct Hvalid as [? Hf].
  assert (Hfb: f b)
    by (rewrite Hf; auto).
  specialize (Hincr b Hfb).
  destruct (f' b) eqn:Hf'; try by exfalso.
    by eexists; eauto.
Qed.

Lemma valid_val_list_incr:
  forall f f' vs
    (Hvalid: valid_val_list f vs)
    (Hincr: ren_domain_incr f f'),
    valid_val_list f' vs.
Proof.
  intros.
  induction vs;
    first by constructor.
  inversion Hvalid; subst.
  constructor; eauto.
  eapply valid_val_incr;
    by eauto.
Qed.
  
Lemma restrPermMap_val_valid:
  forall m p (Hlt: permMapLt p (getMaxPerm m)) v,
    mem_wd.val_valid v m <-> mem_wd.val_valid v (restrPermMap Hlt).
Proof.
  intros; split; unfold mem_wd.val_valid;
    by destruct v.
Qed.

Lemma restrPermMap_mem_valid :
  forall m p (Hlt: permMapLt p (getMaxPerm m)),
    valid_mem m <-> valid_mem (restrPermMap Hlt).
Proof.
  intros.
  split; intros Hvalid b;
  specialize (Hvalid b);
  erewrite restrPermMap_valid in *; simpl; intros Hb ofs mv Hmv;
  specialize (Hvalid Hb ofs mv Hmv);
  destruct mv; auto.
Qed.

Lemma valid_val_domain:
  forall f f' m v,
    valid_val f v ->
    domain_memren f m ->
    domain_memren f' m ->
    valid_val f' v.
Proof.
  intros.
  destruct v; auto.
  destruct H as [b' Hf].
  unfold domain_memren in *.
  destruct (H0 b).
  destruct (H1 b).
  rewrite Hf in H2.
  specialize (H2 ltac:(auto)).
  specialize (H3 H2).
  destruct (f' b) eqn:Hf'; try by exfalso.
  econstructor; eauto.
Qed.

Lemma valid_val_list_domain:
  forall f f' m vs
    (Hvalid: valid_val_list f vs)
    (Hdomain: domain_memren f m)
    (Hdomain': domain_memren f' m),
    valid_val_list f' vs.
Proof.
  intros.
  induction vs; first by constructor.
  inversion Hvalid; subst.
  constructor; [eapply valid_val_domain|];
    by eauto.
Qed.

(** Well-definedeness is preserved through storing a well-defined value *)
Lemma store_wd:
  forall m m' chunk b ofs v
    (Hstore: Mem.store chunk m b ofs v = Some m')
    (Hval_wd: mem_wd.val_valid v m)
    (Hmem_wd: valid_mem m),
    valid_mem m'.
Proof.
Admitted.
(*intros.
            intros b' Hvalid' ofs' mv' Hget.
            assert (Hvalid := Mem.store_valid_access_3 _ _ _ _ _ _ Hstore).
            eapply Mem.valid_access_implies with (p2 := Nonempty) in Hvalid;
              try constructor.
            eapply Mem.valid_access_valid_block in Hvalid.
            destruct mv'; auto.
            assert (Hcontents := Mem.store_mem_contents _ _ _ _ _ _ Hstore).
            rewrite Hcontents in Hget. clear Hcontents.
            destruct (Pos.eq_dec b b') as [Heq | Hneq].
            (*case it's the same block*)
            subst.
            rewrite Maps.PMap.gss in Hget.
            destruct v, chunk; simpl in *. Focus 3.
            try match goal with
                | [H: Maps.ZMap.get ?Ofs (Maps.ZMap.set ?Ofs' _ _) = _ |- _] =>
                  destruct (Z.eq_dec Ofs Ofs'); subst
                end;
            try match goal with
                | [H: Maps.ZMap.get ?Ofs (Maps.ZMap.set ?Ofs _ _) = _ |- _] =>
                  rewrite Maps.ZMap.gss in H
                | [H: Maps.ZMap.get ?Ofs (Maps.ZMap.set ?Ofs' _ _) = _,
                      H1: ?Ofs <> ?Ofs' |- _] =>
                  rewrite Maps.ZMap.gso in H; auto
                end;
            try discriminate;
            unfold mem_wd.val_valid;
            destruct v0; auto;
            try (specialize (Hmem_wd b' Hvalid ofs' _ Hget);
                  simpl in Hmem_wd);
            try (by (eapply Mem.store_valid_block_1; eauto)).
            try match goal with
                | [H: Maps.ZMap.get ?ofS (Maps.ZMap.set ?Ofs _ _) = _ |- _] =>
                  destruct (Z.eq_dec ofs' Ofs); subst
                end.
            
            try rewrite Maps.ZMap.gss in Hget;
            try discriminate. *)

End MemoryWD.

Module MemoryLemmas.

  (*TODO: see if we can reuse that for gsoMem_obs_eq.*)
  Lemma store_contents_other:
    forall m m' b b' ofs ofs' v chunk
      (Hstore: Mem.store chunk m b ofs v = Some m')
      (Hstable: ~ Mem.perm m b' ofs' Cur Writable),
      Maps.ZMap.get ofs' (Mem.mem_contents m') # b' =
      Maps.ZMap.get ofs' (Mem.mem_contents m) # b'.
  Proof.
    intros.
    erewrite Mem.store_mem_contents; eauto.
    simpl.
    destruct (Pos.eq_dec b b') as [Heq | Hneq];
      [| by erewrite Maps.PMap.gso by auto].
    subst b'.
    rewrite Maps.PMap.gss.
    destruct (Z_lt_le_dec ofs' ofs) as [Hlt | Hge].
    erewrite Mem.setN_outside by (left; auto);
      by reflexivity.
    destruct (Z_lt_ge_dec
                ofs' (ofs + (size_chunk chunk)))
      as [Hlt | Hge'].
    (* case the two addresses coincide - contradiction*)
    apply Mem.store_valid_access_3 in Hstore.
    unfold Mem.valid_access in Hstore. simpl in Hstore.
    destruct Hstore as [Hcontra _].
    unfold Mem.range_perm in Hcontra.
    specialize (Hcontra ofs' (conj Hge Hlt));
      by exfalso.
    erewrite Mem.setN_outside by (right; rewrite size_chunk_conv in Hge';
                                    by rewrite encode_val_length);
      by auto.
  Qed.

  Transparent Mem.alloc.
  
  Lemma val_at_alloc_1:
    forall m m' sz nb b ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb))
      (Hvalid: Mem.valid_block m b),
      Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m)) =
      Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m')).
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    simpl.
    rewrite Maps.PMap.gso; auto.
    intro; subst. unfold Mem.valid_block in *.
    eapply Plt_strict; eauto.
  Qed.

  Lemma val_at_alloc_2:
    forall m m' sz nb ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb)),
      Maps.ZMap.get ofs (Maps.PMap.get nb (Mem.mem_contents m')) = Undef.
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    simpl.
    rewrite Maps.PMap.gss Maps.ZMap.gi.
    reflexivity.
  Qed.

  Lemma permission_at_alloc_1:
    forall m m' sz nb b ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb))
      (Hvalid: Mem.valid_block m b),
      permissions.permission_at m b ofs Cur =
      permissions.permission_at m' b ofs Cur.
  Proof.
    intros.
    Transparent Mem.alloc.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    unfold permissions.permission_at. simpl.
    rewrite Maps.PMap.gso; auto.
    intro; subst. unfold Mem.valid_block in *.
    eapply Plt_strict; eauto.
  Qed.

  Lemma permission_at_alloc_2:
    forall m m' sz nb ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb))
      (Hofs: (0 <= ofs < sz)%Z),
      permissions.permission_at m' nb ofs Cur = Some Freeable.
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    unfold permissions.permission_at. simpl.
    rewrite Maps.PMap.gss.
    rewrite if_true; auto.
    destruct (zle 0 ofs), (zlt ofs sz); auto;
    try omega.
  Qed.

  Lemma permission_at_alloc_3:
    forall m m' sz nb ofs
      (Halloc: Mem.alloc m 0 sz = (m', nb))
      (Hofs: (ofs < 0 \/ ofs >= sz)%Z),
      permissions.permission_at m' nb ofs Cur = None.
  Proof.
    intros.
    unfold Mem.alloc in Halloc.
    inv Halloc.
    unfold permissions.permission_at. simpl.
    rewrite Maps.PMap.gss.
    rewrite if_false; auto.
    apply negb_true_iff.
    destruct (zle 0 ofs), (zlt ofs sz); auto;
    omega.
  Qed.

  Lemma mem_free_contents:
    forall m m2 sz b
      (Hfree: Mem.free m b 0 sz = Some m2),
    forall b' ofs,
      Maps.ZMap.get ofs (Maps.PMap.get b' (Mem.mem_contents m)) =
      Maps.ZMap.get ofs (Maps.PMap.get b' (Mem.mem_contents m2)).
  Proof.
    intros.
    apply Mem.free_result in Hfree.
    subst; unfold Mem.unchecked_free.
    reflexivity.
  Qed.
  
End MemoryLemmas.

(** ** Injections on values*)
Module ValObsEq.

  Import MemoryWD Renamings MemoryLemmas.
  
  (** Strong injections on values *)
  Inductive val_obs (mi : memren) : val -> val -> Prop :=
    obs_int : forall i : int, val_obs mi (Vint i) (Vint i)
  | obs_long : forall i : int64, val_obs mi (Vlong i) (Vlong i)
  | obs_float : forall f : Floats.float,
      val_obs mi (Vfloat f) (Vfloat f)
  | obs_single : forall f : Floats.float32,
      val_obs mi (Vsingle f) (Vsingle f)
  | obs_ptr : forall (b1 b2 : block) (ofs : int),
      mi b1 = Some b2 ->
      val_obs mi (Vptr b1 ofs) (Vptr b2 ofs)
  | obs_undef : val_obs mi Vundef Vundef.

  (** Strong injections on memory values*)
  Inductive memval_obs_eq (f : memren) : memval -> memval -> Prop :=
  | memval_obs_byte : forall n : byte,
      memval_obs_eq f (Byte n) (Byte n)
  | memval_obs_frag : forall (v1 v2 : val) (q : quantity) (n : nat)
                        (Hval_obs: val_obs f v1 v2),
      memval_obs_eq f (Fragment v1 q n) (Fragment v2 q n)
  | memval_obs_undef : memval_obs_eq f Undef Undef.

  
  Inductive val_obs_list (mi : memren) : seq val -> seq val -> Prop :=
    val_obs_list_nil : val_obs_list mi [::] [::]
  | val_obs_list_cons : forall (v v' : val) (vl vl' : seq val),
                       val_obs mi v v' ->
                       val_obs_list mi vl vl' ->
                       val_obs_list mi (v :: vl) (v' :: vl').

  Hint Constructors val_obs : val_renamings.
  
  Lemma val_obs_incr:
    forall f f' v v'
      (Hval_obs: val_obs f v v')
      (Hincr: ren_incr f f'),
      val_obs f' v v'.
  Proof with eauto with val_renamings.
    intros.
    destruct v; inversion Hval_obs; subst...
  Qed.
      
  Lemma val_obs_trans:
    forall (v v' v'' : val) (f f' f'' : memren),
      val_obs f v v'' ->
      val_obs f' v v' ->
      (forall b b' b'' : block,
          f b = Some b'' ->
          f' b = Some b' ->
          f'' b' = Some b'') -> 
      val_obs f'' v' v''.
  Proof with eauto with val_renamings.
    intros v v' v'' f f' f'' Hval'' Hval' Hf.
    inversion Hval'; subst; inversion Hval''; subst...
  Qed.

  Lemma memval_obs_trans:
    forall (v v' v'' : memval) (f f' f'' : memren),
      memval_obs_eq f v v'' ->
      memval_obs_eq f' v v' ->
      (forall b b' b'' : block,
          f b = Some b'' ->
          f' b = Some b' ->
          f'' b' = Some b'') -> 
      memval_obs_eq f'' v' v''.
  Proof.
    intros v v' v'' f f' f'' Hval'' Hval' Hf.
    inversion Hval'; subst; inversion Hval''; subst;
    try constructor.
    eapply val_obs_trans;
      by eauto.
  Qed.
 
  Lemma val_obs_list_trans:
    forall (vs vs' vs'' : seq val) (f f' f'' : memren),
      val_obs_list f vs vs'' ->
      val_obs_list f' vs vs' ->
      (forall b b' b'' : block,
          f b = Some b'' ->
          f' b = Some b' ->
          f'' b' = Some b'') ->
      val_obs_list f'' vs' vs''.
  Proof.
    intros vs vs' vs'' f f' f'' Hobs Hobs' Hf.
    generalize dependent vs''.
    induction Hobs'; subst; intros;
    inversion Hobs; subst. constructor.
    constructor; auto.
      by eapply val_obs_trans; eauto.
  Qed.

  Lemma val_obs_list_incr:
    forall (vs vs' : seq val) (f f' : memren),
      val_obs_list f vs vs' ->
      ren_incr f f' ->
      val_obs_list f' vs vs'.
  Proof.
    intros.
    induction H;
      constructor;
      eauto using val_obs_incr.
  Qed.
    
  (** Two values that are equal are related by the id injection on a valid memory*)
  Lemma val_obs_id:
    forall f v
      (Hvalid: valid_val f v)
      (Hid: forall b b', f b = Some b' -> b = b'),
      val_obs f v v.
  Proof with eauto with val_renamings.
    intros.
    destruct v...
    destruct Hvalid as [b' Hf].
    specialize (Hid _ _ Hf);
      subst...
  Qed.

  Lemma val_obs_list_id :
    forall f vs
      (Hvalid: valid_val_list f vs)
      (Hf: forall b1 b2, f b1 = Some b2 -> b1 = b2),
      val_obs_list f vs vs.
  Proof.
    intros.
    induction vs; first by constructor.
    inversion Hvalid; subst.
    constructor;
      [eapply val_obs_id; eauto | eauto].
  Qed.
  
  Lemma memval_obs_eq_id:
    forall f mv
      (Hvalid: valid_memval f mv)
      (Hid: forall b b', f b = Some b' -> b = b'),
                    memval_obs_eq f mv mv.
  Proof.
    intros.
    destruct mv;
    econstructor;
    eapply val_obs_id;
      by eauto.
  Qed.

  Lemma ren_cmp_bool:
    forall f v v' v0 cmp,
      val_obs f v v' ->
      Val.cmp_bool cmp v v0 = Val.cmp_bool cmp v' v0.
  Proof.
    intros.
    destruct v; inversion H; subst;
      by reflexivity.
  Qed.

  Lemma val_obs_hiword:
    forall f v v',
      val_obs f v v' ->
      val_obs f (Val.hiword v) (Val.hiword v').
  Proof with eauto with val_renamings.
    intros;
    destruct v; inversion H; subst;
    simpl...
  Qed.

  Lemma val_obs_loword:
    forall f v v',
      val_obs f v v' ->
      val_obs f (Val.loword v) (Val.loword v').
  Proof with eauto with val_renamings.
    intros;
    destruct v; inversion H; subst;
    simpl...
  Qed.

  Lemma val_obs_longofwords:
    forall f vhi vhi' vlo vlo'
      (Hobs_hi: val_obs f vhi vhi')
      (Hobs_lo: val_obs f vlo vlo'),
      val_obs f (Val.longofwords vhi vlo) (Val.longofwords vhi' vlo').
  Proof with eauto with val_renamings.
    intros;
    destruct vhi; inversion Hobs_hi; subst; simpl...
    destruct vlo; inversion Hobs_lo...
  Qed.

  Lemma val_obs_load_result:
    forall f v v' chunk
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.load_result chunk v) (Val.load_result chunk v').
  Proof with eauto with val_renamings.
    intros;
    destruct v; inversion Hval_obs; subst;
    destruct chunk; simpl...
  Qed.

  Lemma val_obs_ext:
    forall f v v' n
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.zero_ext n v) (Val.zero_ext n v').
  Proof with eauto with val_renamings.
    intros; destruct v; inversion Hval_obs; subst; simpl...
  Qed.
  
  Definition val_obsC f v :=
    match v with
    | Vptr b n => match f b with
                 | Some b' => Vptr b' n
                 | None => Vundef
                 end
    | _ => v
    end.

  Lemma val_obsC_correct:
    forall f v,
      valid_val f v ->
      val_obs f v (val_obsC f v).
  Proof.
    intros.
    destruct v; simpl;
    try constructor.
    simpl in H.
    destruct H.
    rewrite H;
      by constructor.
  Qed.

  Lemma val_has_type_obs:
    forall f v v' ty
      (Hval_obs: val_obs f v v'),
      val_casted.val_has_type_func v ty <-> val_casted.val_has_type_func v' ty.
  Proof.
    intros.
    destruct v; inversion Hval_obs; subst; simpl;
      by tauto.
  Qed.
  
  Lemma val_has_type_list_obs:
    forall f vs vs' ts
      (Hval_obs: val_obs_list f vs vs'),
      val_casted.val_has_type_list_func vs ts <->
      val_casted.val_has_type_list_func vs' ts.
  Proof.
    intros.
    generalize dependent vs'.
    generalize dependent ts.
    induction vs;
      intros. inversion Hval_obs; subst.
    simpl; destruct ts; split;
      by auto.
    inversion Hval_obs; subst.
    destruct ts; simpl; first by split; auto.
    split; intros; move/andP:H=>[H H'];
      apply/andP.
    split;
      [erewrite <- val_has_type_obs; eauto |
       destruct (IHvs ts _ H3); eauto].
    split;
      [erewrite val_has_type_obs; eauto |
       destruct (IHvs ts _ H3); eauto].
  Qed.

  Lemma vals_defined_obs:
    forall f vs vs'
      (Hval_obs: val_obs_list f vs vs'),
      val_casted.vals_defined vs <-> val_casted.vals_defined vs'.
  Proof.
    intros.
    induction Hval_obs;
      simpl; try tauto.
    destruct v; inversion H;
      by tauto.
  Qed.

  Lemma zlength_obs:
    forall f v v'
      (Hval_obs: val_obs_list f v v'),
      Zlength v = Zlength v'.
  Proof.
    induction 1; simpl; auto.
    do 2 rewrite Zlength_cons;
      by rewrite IHHval_obs.
  Qed.

  Lemma val_obs_add:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.add v1 v1') (Val.add v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_sign_ext:
    forall f v v' n
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.sign_ext n v) (Val.sign_ext n v').
  Proof with eauto with val_renamings.
    intros; destruct v; inversion Hval_obs; subst; simpl...
  Qed.
  
  
  Lemma val_obs_singleoffloat:
    forall f v v'
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.singleoffloat v) (Val.singleoffloat v').
  Proof with eauto with val_renamings.
    intros; destruct v; inversion Hval_obs; subst; simpl...
  Qed.

  Lemma val_obs_floatofsingle:
    forall f v v'
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.floatofsingle v) (Val.floatofsingle v').
  Proof with eauto with val_renamings.
    intros; destruct v; inversion Hval_obs; subst; simpl...
  Qed.

  Lemma val_obs_intoffloat:
    forall f v v'
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.maketotal (Val.intoffloat v))
              (Val.maketotal (Val.intoffloat v')).
  Proof with eauto with val_renamings.
    intros; destruct v; unfold Val.maketotal;
    inversion Hval_obs; subst; simpl...
    match goal with
    | [|- context[match ?Expr with _ => _ end]] =>
      destruct Expr eqn:?
    end...
    unfold Coqlib.option_map in Heqo.
    destruct (Floats.Float.to_int f0); inversion Heqo...
  Qed.

  Lemma val_obs_floatofint:
    forall f v v'
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.maketotal (Val.floatofint v))
              (Val.maketotal (Val.floatofint v')).
  Proof with eauto with val_renamings.
    intros; destruct v; unfold Val.maketotal;
    inversion Hval_obs; subst; simpl...
  Qed.

  Lemma val_obs_intofsingle:
    forall f v v'
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.maketotal (Val.intofsingle v))
              (Val.maketotal (Val.intofsingle v')).
  Proof with eauto with val_renamings.
    intros; destruct v; unfold Val.maketotal;
    inversion Hval_obs; subst; simpl...
    match goal with
    | [|- context[match ?Expr with _ => _ end]] =>
      destruct Expr eqn:?
    end...
    unfold Coqlib.option_map in Heqo.
    destruct (Floats.Float32.to_int f0); inversion Heqo...
  Qed.
  
  Lemma val_obs_singleofint:
    forall f v v'
      (Hval_obs: val_obs f v v'),
      val_obs f (Val.maketotal (Val.singleofint v))
              (Val.maketotal (Val.singleofint v')).
  Proof with eauto with val_renamings.
    intros; destruct v; unfold Val.maketotal;
    inversion Hval_obs; subst; simpl...
  Qed.

  Lemma val_obs_mul:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.mul v1 v1') (Val.mul v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_mulhs:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.mulhs v1 v1') (Val.mulhs v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_mulhu:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.mulhu v1 v1') (Val.mulhu v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.
  
  Lemma val_obs_and:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.and v1 v1') (Val.and v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.
  
  Lemma val_obs_or:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.or v1 v1') (Val.or v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_xor:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.xor v1 v1') (Val.xor v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_notint:
    forall f v1 v2
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.notint v1) (Val.notint v2).
  Proof with eauto with val_renamings.
    intros.
    destruct v1; inversion Hval_obs; subst;
    simpl...
  Qed.

  Lemma val_obs_shl:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.shl v1 v1') (Val.shl v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
    destruct (Int.ltu i0 Int.iwordsize)...
  Qed.

  Lemma val_obs_shr:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.shr v1 v1') (Val.shr v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
    destruct (Int.ltu i0 Int.iwordsize)...
  Qed.

  
  Lemma val_obs_shru:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.shru v1 v1') (Val.shru v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
    destruct (Int.ltu i0 Int.iwordsize)...
  Qed.

  Lemma val_obs_ror:
  forall f v1 v2 ofs
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.ror v1 (Vint ofs)) (Val.ror v2 (Vint ofs)).
  Proof with eauto with val_renamings.
    intros.
    destruct v1; inversion Hval_obs; subst;
    simpl...
    destruct (Int.ltu ofs Int.iwordsize)...
  Qed.

  Lemma val_obs_suboverflow:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.sub_overflow v1 v1') (Val.sub_overflow v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_negative:
    forall f v1 v2
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.negative v1) (Val.negative v2).
  Proof with eauto with val_renamings.
    intros.
    destruct v1; inversion Hval_obs; subst;
    simpl...
  Qed.

  Lemma val_obs_neg:
    forall f v1 v2
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.neg v1) (Val.neg v2).
  Proof with eauto with val_renamings.
    intros.
    destruct v1; inversion Hval_obs; subst;
    simpl...
  Qed.

  Lemma val_obs_sub:
    forall f v1 v2 v1' v2'
      (Hinjective: forall b1 b1' b2,
          f b1 = Some b2 -> f b1' = Some b2 -> b1 = b1')
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.sub v1 v1') (Val.sub v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
    destruct (eq_block b b0); subst.
    rewrite H6 in H2; inversion H2; subst.
    destruct (eq_block b2 b2)...
      by exfalso.
      destruct (eq_block b2 b4)...
      subst.
      assert (b0 = b)
        by (eapply Hinjective; eauto).
      subst.
        by exfalso.
  Qed.

  (** Floating point functions *)
  Lemma val_obs_addf:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.addf v1 v1') (Val.addf v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_addfs:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.addfs v1 v1') (Val.addfs v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_mulf:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.mulf v1 v1') (Val.mulf v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_mulfs:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.mulfs v1 v1') (Val.mulfs v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_negf:
    forall f v1 v2
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.negf v1) (Val.negf v2).
  Proof with eauto with val_renamings.
    intros.
    destruct v1; inversion Hval_obs;
    subst; simpl...
  Qed.

  Lemma val_obs_negfs:
    forall f v1 v2
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.negfs v1) (Val.negfs v2).
  Proof with eauto with val_renamings.
    intros.
    destruct v1; inversion Hval_obs;
    subst; simpl...
  Qed.
  
  Lemma val_obs_absf:
    forall f v1 v2
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.absf v1) (Val.absf v2).
  Proof with eauto with val_renamings.
    intros.
    destruct v1; inversion Hval_obs;
    subst; simpl...
  Qed.

  Lemma val_obs_absfs:
    forall f v1 v2
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.absfs v1) (Val.absfs v2).
  Proof with eauto with val_renamings.
    intros.
    destruct v1; inversion Hval_obs;
    subst; simpl...
  Qed.

  Lemma val_obs_subf:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.subf v1 v1') (Val.subf v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_subfs:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.subfs v1 v1') (Val.subfs v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_divf:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.divf v1 v1') (Val.divf v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma val_obs_divfs:
    forall f v1 v2 v1' v2'
      (Hval_obs': val_obs f v1' v2')
      (Hval_obs: val_obs f v1 v2),
      val_obs f (Val.divfs v1 v1') (Val.divfs v2 v2').
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v1'; inversion Hval_obs;
    inversion Hval_obs'; subst; simpl...
  Qed.

  Lemma divu_ren:
    forall f v1 v2 v1' v2'
      (Hval_obs: val_obs f v1 v1')
      (Hval_obs': val_obs f v2 v2'),
      Val.divu v1 v2 = Val.divu v1' v2'.
  Proof.
    intros.
    destruct v1; inversion Hval_obs; subst;
    destruct v2; inversion Hval_obs'; subst; simpl in *;
    auto.
  Qed.

  Lemma modu_ren:
    forall f v1 v2 v1' v2'
      (Hval_obs: val_obs f v1 v1')
      (Hval_obs': val_obs f v2 v2'),
      Val.modu v1 v2 = Val.modu v1' v2'.
  Proof.
    intros.
    destruct v1; inversion Hval_obs; subst;
    destruct v2; inversion Hval_obs'; subst; simpl in *;
    auto.
  Qed.

  Lemma val_obs_divu_id:
    forall f v1 v2 v,
      Val.divu v1 v2 = Some v ->
      val_obs f v v.
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v2; simpl in *; try discriminate.
    destruct (Int.eq i0 Int.zero); try discriminate.
    inversion H...
  Qed.

  Lemma val_obs_modu_id:
    forall f v1 v2 v,
      Val.modu v1 v2 = Some v ->
      val_obs f v v.
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v2; simpl in *; try discriminate.
    destruct (Int.eq i0 Int.zero); try discriminate.
    inversion H...
  Qed.

  Lemma divs_ren:
    forall f v1 v2 v1' v2'
      (Hval_obs: val_obs f v1 v1')
      (Hval_obs': val_obs f v2 v2'),
      Val.divs v1 v2 = Val.divs v1' v2'.
  Proof.
    intros.
    destruct v1; inversion Hval_obs; subst;
    destruct v2; inversion Hval_obs'; subst; simpl in *;
    auto.
  Qed.

  Lemma mods_ren:
    forall f v1 v2 v1' v2'
      (Hval_obs: val_obs f v1 v1')
      (Hval_obs': val_obs f v2 v2'),
      Val.mods v1 v2 = Val.mods v1' v2'.
  Proof.
    intros.
    destruct v1; inversion Hval_obs; subst;
    destruct v2; inversion Hval_obs'; subst; simpl in *;
    auto.
  Qed.

  Lemma val_obs_divs_id:
    forall f v1 v2 v,
      Val.divs v1 v2 = Some v ->
      val_obs f v v.
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v2; simpl in *; try discriminate.
    match goal with
    | [H: match ?Expr with _ => _ end = _ |- _] =>
      destruct Expr
    end; try discriminate.
    inversion H...
  Qed.

  Lemma val_obs_mods_id:
    forall f v1 v2 v,
      Val.mods v1 v2 = Some v ->
      val_obs f v v.
  Proof with eauto with val_renamings.
    intros.
    destruct v1, v2; simpl in *; try discriminate.
    match goal with
    | [H: match ?Expr with _ => _ end = _ |- _] =>
      destruct Expr
    end; try discriminate.
    inversion H...
  Qed.
  
  Hint Resolve
       val_obs_add valid_val_incr val_obs_incr val_obsC_correct
       val_obs_load_result val_obs_hiword val_obs_loword
       val_obs_longofwords val_obs_load_result val_obs_ext
       val_obs_sign_ext val_obs_singleoffloat val_obs_floatofsingle
       val_obs_intoffloat val_obs_floatofint val_obs_intofsingle
       val_obs_singleofint val_obs_neg
       val_obs_mul val_obs_mulhs val_obs_mulhu
       val_obs_and val_obs_sub
       val_obs_or val_obs_xor val_obs_notint
       val_obs_shl val_obs_shr val_obs_shru
       val_obs_ror val_obs_suboverflow val_obs_negative
       val_obs_addf val_obs_addfs val_obs_mulf
       val_obs_mulfs val_obs_negf val_obs_negfs
       val_obs_absf val_obs_absfs val_obs_subf
       val_obs_subfs val_obs_divf val_obs_divfs
       val_obs_divu_id val_obs_modu_id
       val_obs_divs_id val_obs_mods_id: val_renamings.
  
End ValObsEq.
  
(** ** Injections between memories *)
Module MemObsEq.

  Import ValObsEq SEM MemoryWD Renamings MemoryLemmas.

  (* A compcert injection would not work because it allows permissions to go up *)
  (* Moreover, we require that undefined values are matched by the target memory,
     unlike compcert injections *)
  
  (** Weak injection between memories *)
  Record weak_mem_obs_eq (f : memren) (mc mf : mem) :=
    {
      domain_invalid: forall b, ~(Mem.valid_block mc b) -> f b = None;
      domain_valid: forall b, Mem.valid_block mc b -> exists b', f b = Some b';
      codomain_valid: forall b1 b2, f b1 = Some b2 -> Mem.valid_block mf b2;
      injective: forall b1 b1' b2, f b1 = Some b2 ->
                              f b1' = Some b2 ->
                              b1 = b1';
      perm_obs_weak :
        forall b1 b2 ofs (Hrenaming: f b1 = Some b2),
          Mem.perm_order''
            (permission_at mc b1 ofs Cur)
            (permission_at mf b2 ofs Cur)}.

 

  (** Strong injection between memories *)
  Record strong_mem_obs_eq (f : memren) (mc mf : mem) :=
    { perm_obs_strong :
        forall b1 b2 ofs (Hrenaming: f b1 = Some b2),
            permission_at mf b2 ofs Cur =
            (permission_at mc b1 ofs Cur);
      val_obs_eq :
        forall b1 b2 ofs (Hrenaming: f b1 = Some b2)
          (Hperm: Mem.perm mc b1 ofs Cur Readable),
          memval_obs_eq f (Maps.ZMap.get ofs mc.(Mem.mem_contents)#b1)
                        (Maps.ZMap.get ofs mf.(Mem.mem_contents)#b2)}.

  
  (** Strong injection between memories *)
  Record mem_obs_eq (f : memren) (mc mf : mem) :=
    { weak_obs_eq : weak_mem_obs_eq f mc mf;
      strong_obs_eq : strong_mem_obs_eq f mc mf }.

  Lemma weak_obs_eq_domain_ren:
    forall f m m',
      weak_mem_obs_eq f m m' ->
      domain_memren f m.
  Proof.
    intros f m m' Hobs_eq.
    destruct Hobs_eq.
    intros b. split;
    intros Hb.
    specialize (domain_valid0 _ Hb).
    destruct (domain_valid0) as [? H].
    rewrite H;
      by auto.
    destruct (valid_block_dec m b); auto.
    specialize (domain_invalid0 _ n).
    rewrite domain_invalid0 in Hb;
      by exfalso.
  Qed.

  Corollary mem_obs_eq_domain_ren:
    forall f m m',
      mem_obs_eq f m m' ->
      domain_memren f m.
  Proof.
    intros f m m' H; destruct H;
    eapply weak_obs_eq_domain_ren;
      by eauto.
  Qed.
  
  Definition max_inv mf := forall b ofs, Mem.valid_block mf b ->
                                    permission_at mf b ofs Max = Some Freeable.

  Lemma max_inv_store:
    forall m m' chunk b ofs v pmap
      (Hlt: permMapLt pmap (getMaxPerm m))
      (Hmax: max_inv m)
      (Hstore: Mem.store chunk (restrPermMap Hlt) b ofs v = Some m'),
      max_inv m'.
  Proof.
    intros.
    intros b0 ofs0 Hvalid0.
    unfold permission_at.
    erewrite Mem.store_access; eauto.
    assert (H := restrPermMap_Max Hlt b0 ofs0).
    eapply Mem.store_valid_block_2 in Hvalid0; eauto.
    erewrite restrPermMap_valid in Hvalid0.
    specialize (Hmax b0 ofs0 Hvalid0).
    unfold permission_at in H.
    rewrite H.
    rewrite getMaxPerm_correct;
      by assumption.
  Qed.
  
  Lemma sim_valid_access:
    forall (mf m1f : mem) 
      (b1 b2 : block) (ofs : int)
      (Hm1f: m1f = makeCurMax mf)
      (HmaxF: max_inv mf)
      (Hvalidb2: Mem.valid_block mf b2)
      (Halign: (4 | Int.intval ofs)%Z),
      Mem.valid_access m1f Mint32 b2 (Int.intval ofs) Freeable.
  Proof.          
    unfold Mem.valid_access. simpl. split; try assumption.
    unfold Mem.range_perm. intros ofs0 Hbounds. subst m1f.
    specialize (HmaxF _ ofs0 Hvalidb2).
    unfold Mem.perm.
    assert (Hperm := makeCurMax_correct mf b2 ofs0 Cur).
    rewrite HmaxF in Hperm.
    unfold permission_at in Hperm.
    unfold Mem.perm.
    rewrite <- Hperm.
    simpl;
      by constructor.
  Qed.

  Lemma mf_align :
    forall (m : mem) (f : memren) (b1 b2 : block) (delta : Z) (chunk : memory_chunk)
      (ofs : Z) (p : permission),
      f b1 = Some b2 ->
      Mem.range_perm m b1 ofs (ofs + size_chunk chunk) Max p ->
      (align_chunk chunk | 0%Z)%Z.
  Proof.
    intros.
      by apply mem_wd.align_chunk_0.
  Qed.

  (* Obs_eq is a compcert injection*)

    (*
  Lemma val_obs_eq_inj :
    forall f v1 v2,
      val_obs f v1 v2 ->
      val_inject f v1 v2
  Proof.
    intros f v1 v2 Hobs_eq.
    inversion Hobs_eq;
      try (split; [constructor | auto]).
    subst.
    split; try congruence.
    eapply Val.inject_ptr with (delta := 0%Z); eauto.
      by rewrite Int.add_zero.
  Qed.

  Lemma memval_obs_eq_inj :
    forall f mv1 mv2,
      memval_obs_eq f mv1 mv2 ->
      memval_inject f mv1 mv2
      /\ (mv1 = Undef -> mv2 = Undef).
  Proof.
    intros f mv1 mv2 Hobs_eq.
    inversion Hobs_eq;
      split; try constructor; try auto.
    inversion Hval_obs; subst; try constructor.
      by eapply val_obs_eq_inj.
        by congruence.
  Qed.
  
  Theorem mem_obs_eq_mem_inj:
    forall mc mf f,
      mem_obs_eq f mc mf ->
      max_inv mf ->
      Mem.mem_inj f mc mf.
  Proof.
    intros mc mf f Hobs_eq HmaxF.
    destruct Hobs_eq as [Hweak [HpermStrong Hval]].
    constructor.
    - intros b1 b2 delta ofs k p Hf Hperm.
      assert (delta = 0%Z)
        by (eapply (weak_mem_obs_eq_f _ Hweak Hf); eauto); subst.
      rewrite Zplus_0_r.
      specialize (HpermStrong _ _ ofs Hf).
      unfold Mem.perm in *.
      unfold permission_at in HpermStrong.
      rewrite po_oo in Hperm. rewrite po_oo.
      destruct k.
      apply (codomain_valid Hweak) in Hf.
      specialize (HmaxF _ ofs Hf). unfold permission_at in HmaxF.
      rewrite HmaxF.
      simpl;
        by constructor.
      rewrite HpermStrong. eauto.
    - intros b1 b2 delta chunk ofs p Hf _.
      assert (delta = 0%Z)
        by (eapply (weak_mem_obs_eq_f _ Hweak Hf); eauto);
        subst;
          by apply mem_wd.align_chunk_0.
    - intros b1 ofs b2 delta Hf Hreadable.
      assert (delta = 0%Z)
        by (eapply (weak_mem_obs_eq_f _ Hweak Hf); eauto);
        subst.
      specialize (Hval _ _ _ Hf Hreadable).
      rewrite Zplus_0_r.
      eapply memval_obs_eq_inj; eauto.
      
  Qed. *)

  Lemma memval_obs_eq_incr:
    forall (mc mf : mem) (f f': memren) 
      (b1 b2 : block) (ofs : Z)
      (Hf': f' b1 = Some b2)
      (Hincr: ren_incr f f')
      (Hobs_eq: memval_obs_eq f (Maps.ZMap.get ofs (Mem.mem_contents mc) # b1)
                              (Maps.ZMap.get ofs (Mem.mem_contents mf) # b2)),
      memval_obs_eq f' (Maps.ZMap.get ofs (Mem.mem_contents mc) # b1)
                    (Maps.ZMap.get ofs (Mem.mem_contents mf) # b2).
  Proof.
    intros.
    inversion Hobs_eq;
      constructor.
    inversion Hval_obs; subst; constructor.
    apply Hincr in H1.
      by auto.
  Qed.

  (* Don't really care about this right now*)
  (* Lemma mem_inj_dillute: *)
  (*   forall mc mf f, *)
  (*     Mem.mem_inj f mc mf -> *)
  (*     Mem.mem_inj f mc (makeCurMax mf). *)
  (* Admitted. *)


  (* Proof as in compcert*)
  Lemma proj_bytes_obs:
    forall (f : memren) (vl vl' : seq memval),
      Coqlib.list_forall2 (memval_obs_eq f) vl vl' ->
      forall bl : seq byte,
        proj_bytes vl = Some bl -> proj_bytes vl' = Some bl.
  Proof.
    induction 1; simpl. intros. congruence.
    inversion H; subst; try congruence.
    destruct (proj_bytes al); intros.
    inversion H; subst; rewrite (IHlist_forall2 l); auto.
    congruence.
  Qed.

  Lemma proj_bytes_obs_none:
    forall (f : memren) (vl vl' : seq memval),
      Coqlib.list_forall2 (memval_obs_eq f) vl vl' ->
      proj_bytes vl = None -> proj_bytes vl' = None.
  Proof.
    induction 1; simpl. intros.  congruence.
    inversion H; subst; try congruence.
    destruct (proj_bytes al); intros.
    discriminate.
      by rewrite (IHlist_forall2 (Logic.eq_refl _)).
  Qed.
  
  Lemma check_value_obs:
    forall f vl vl',
      Coqlib.list_forall2 (memval_obs_eq f) vl vl' ->
      forall v v' q n,
        check_value n v q vl = true ->
        val_obs f v v' -> v <> Vundef ->
        check_value n v' q vl' = true.
  Proof.
    induction 1; intros; destruct n; simpl in *; auto.
    inversion H; subst; auto.
    apply Bool.andb_true_iff in H1.
    destruct H1.
    apply Bool.andb_true_iff in H1.
    destruct H1.
    apply Bool.andb_true_iff in H1.
    destruct H1.
    apply Coqlib.proj_sumbool_true in H1.
    apply Coqlib.proj_sumbool_true in H6.
    assert (n = n0) by (apply beq_nat_true; auto). subst v1 q0 n0.
    replace v2 with v'.
    unfold Coqlib.proj_sumbool; rewrite ! Coqlib.dec_eq_true.
    rewrite <- beq_nat_refl. simpl; eauto.
    inversion H2; subst; try discriminate; inversion Hval_obs; subst; congruence.
  Qed.

  (*TODO*)
  Lemma proj_value_obs:
    forall f q vl1 vl2,
      Coqlib.list_forall2 (memval_obs_eq f) vl1 vl2 ->
      val_obs f (proj_value q vl1) (proj_value q vl2).
  Proof.
    intros f q vl1 v2 Hlst. unfold proj_value.
    inversion Hlst; subst. constructor.
    inversion H; subst; try constructor.
    
    destruct (check_value (size_quantity_nat q) v1 q (Fragment v1 q0 n :: al)) eqn:B.
    destruct (Val.eq v1 Vundef).
    subst v1.
    inversion Hval_obs.
    subst v2.
    destruct (check_value (size_quantity_nat q) Vundef q
                          (Fragment Vundef q0 n :: bl));
      by auto.
    erewrite check_value_obs; eauto.
    (*TODO: need a lemma about check_value being false, and obs_eq*)
    admit.
  Admitted.
  
  Lemma load_result_obs:
    forall f chunk v1 v2,
      val_obs f v1 v2 ->
      val_obs f (Val.load_result chunk v1) (Val.load_result chunk v2).
  Proof.
    intros. inversion H; destruct chunk; simpl; econstructor; eauto.
  Qed.
  
  Lemma decode_val_obs:
    forall f vl1 vl2 chunk,
      Coqlib.list_forall2 (memval_obs_eq f) vl1 vl2 ->
      val_obs f (decode_val chunk vl1) (decode_val chunk vl2).
  Proof.
    intros f vl1 vl2 chunk Hobs_eq.
    unfold decode_val.
    destruct (proj_bytes vl1) as [bl1|] eqn:PB1.
    eapply proj_bytes_obs with (vl' := vl2) in PB1; eauto.
    rewrite PB1.
    destruct chunk; constructor.
    destruct (proj_bytes vl2) eqn:PB2.
    exfalso.
    eapply proj_bytes_obs_none with (f := f) (vl := vl1) in PB1;
      eauto.
      by congruence.
      destruct chunk; try constructor;
      apply load_result_obs;
      apply proj_value_obs; auto.
  Qed.
  
  
  Lemma load_valid_block:
    forall (m : mem) (b : block) (ofs : int) v,
      Mem.load Mint32 m b (Int.intval ofs) = Some v ->
      Mem.valid_block m b.
  Proof.
    intros m b ofs v Hload.
    apply Mem.load_valid_access in Hload.
    apply Mem.valid_access_valid_block with (chunk:=Mint32) (ofs:= Int.intval ofs).
    eapply Mem.valid_access_implies; eauto.
    constructor.
  Qed.

  (*TODO: The proof. should be easy once we have the lemmas above*)
  Lemma load_val_obs:
    forall (mc mf : mem) (f:memren)
      (b1 b2 : block) chunk (ofs : Z) v1
      (Hload: Mem.load chunk mc b1 ofs = Some v1)
      (Hf: f b1 = Some b2)
      (Hobs_eq: strong_mem_obs_eq f mc mf),
    exists v2,
      Mem.load chunk mf b2 ofs = Some v2 /\
      val_obs f v1 v2.
  Proof.
  Admitted.

  (*TODO: The Proof. Should be same as above*)
  Lemma loadv_val_obs:
    forall (mc mf : mem) (f:memren)
      (vptr1 vptr2 : val) chunk v1
      (Hload: Mem.loadv chunk mc vptr1 = Some v1)
      (Hf: val_obs f vptr1 vptr2)
      (Hobs_eq: strong_mem_obs_eq f mc mf),
    exists v2,
      Mem.loadv chunk mf vptr2 = Some v2 /\
      val_obs f v1 v2.
  Proof.
    Admitted.

  (** ** Lemmas about [Mem.store] and [mem_obs_eq]*)
  (*TODO: The proof*)
  
  Lemma store_val_obs:
    forall (mc mc' mf : mem) (f:memren)
      (b1 b2 : block) chunk (ofs: Z) v1 v2
      (Hload: Mem.store chunk mc b1 ofs v1 = Some mc')
      (Hf: f b1 = Some b2)
      (Hval_obs_eq: val_obs f v1 v2)
      (Hobs_eq: mem_obs_eq f mc mf),
    exists mf',
      Mem.store chunk mf b2 ofs v2 = Some mf' /\
      mem_obs_eq f mc' mf'.
  Proof.
  Admitted.

  Lemma storev_val_obs:
    forall (mc mc' mf : mem) (f:memren)
      (vptr1 vptr2: val) chunk v1 v2
      (Hload: Mem.storev chunk mc vptr1 v1 = Some mc')
      (Hf: val_obs f vptr1 vptr2)
      (Hval_obs_eq: val_obs f v1 v2)
      (Hobs_eq: mem_obs_eq f mc mf),
    exists mf',
      Mem.storev chunk mf vptr2 v2 = Some mf' /\
      mem_obs_eq f mc' mf'.
  Proof.
  Admitted.
  
  Lemma mem_obs_eq_storeF:
    forall f mc mf mf' chunk b ofs v pmap pmap2
      (Hlt: permMapLt pmap (getMaxPerm mf))
      (Hlt': permMapLt pmap (getMaxPerm mf'))
      (Hlt2: permMapLt pmap2 (getMaxPerm mf))
      (Hstore: Mem.store chunk (restrPermMap Hlt2) b ofs v = Some mf')
      (Hdisjoint: permMapsDisjoint pmap pmap2)
      (Hobs_eq: mem_obs_eq f mc (restrPermMap Hlt)),
      mem_obs_eq f mc (restrPermMap Hlt').
  Proof.
    intros.
    destruct Hobs_eq as [Hweak_obs_eq Hstrong_obs_eq].
    destruct Hweak_obs_eq.
    constructor.
    (* weak_obs_eq *)
    constructor; auto.
    intros b1 b2 Hf.
    erewrite restrPermMap_valid.
    specialize (codomain_valid0 _ _ Hf).
    erewrite restrPermMap_valid in codomain_valid0.
    eapply Mem.store_valid_block_1;
      by eauto.
    intros b1 b2 ofs0 Hf.
    specialize (perm_obs_weak0 _ _ ofs0 Hf).
    rewrite restrPermMap_Cur in perm_obs_weak0;
      by rewrite restrPermMap_Cur.
    destruct Hstrong_obs_eq.
    constructor.
    intros b1 b2 ofs0 Hf.
    specialize (perm_obs_strong0 _ _ ofs0 Hf).
    rewrite restrPermMap_Cur in perm_obs_strong0;
      by rewrite restrPermMap_Cur.
    intros b1 b2 ofs0 Hf Hperm.
    simpl.
    specialize (perm_obs_strong0 _ _ ofs0 Hf).
    rewrite restrPermMap_Cur in perm_obs_strong0.
    assert (Hstable: ~ Mem.perm (restrPermMap Hlt2) b2 ofs0 Cur Writable).
    { intros Hcontra.
      assert (Hcur := restrPermMap_Cur Hlt2 b2 ofs0).     
      unfold Mem.perm in *.
      unfold permission_at in *.
      rewrite <- perm_obs_strong0 in Hperm.
      rewrite Hcur in Hcontra.
      specialize (Hdisjoint b2 ofs0).
      eapply perm_order_clash; eauto.
    }
    erewrite store_contents_other with (m := restrPermMap Hlt2) (m' := mf')
      by eauto.
    simpl;
      by auto.
  Qed.

  Lemma alloc_perm_eq:
    forall f m m' sz m2 m2' b b'
      (Hobs_eq: mem_obs_eq f m m')
      (Halloc: Mem.alloc m 0 sz = (m2, b))
      (Halloc': Mem.alloc m' 0 sz = (m2', b'))
      b1 b2 ofs
      (Hf: (if proj_sumbool (valid_block_dec m b1)
            then f b1
            else if proj_sumbool (valid_block_dec m2 b1)
                 then Some b' else None) = Some b2),
      permission_at m2 b1 ofs Cur =
      permission_at m2' b2 ofs Cur.
  Proof.
    intros.
    destruct (valid_block_dec m b1); simpl in Hf.
    - assert (H := perm_obs_strong (strong_obs_eq Hobs_eq) _ ofs Hf).
      erewrite <- permission_at_alloc_1; eauto.
      erewrite <- permission_at_alloc_1 with (m' := m2'); eauto.
      eapply (codomain_valid (weak_obs_eq Hobs_eq));
        by eauto.
    - destruct (valid_block_dec m2 b1); simpl in *; try discriminate.
      inv Hf.
      eapply Mem.valid_block_alloc_inv in v; eauto.
      destruct v; subst; try (by exfalso).
      destruct (zle 0 ofs), (zlt ofs sz);
        [erewrite permission_at_alloc_2 by eauto;
          erewrite permission_at_alloc_2 by eauto;
          reflexivity | | |];
        erewrite permission_at_alloc_3 by (eauto; omega);
        erewrite permission_at_alloc_3 by (eauto; omega);
        auto.
  Qed.

  Lemma mem_free_obs_perm:
    forall f m m' m2 m2' sz b1 b2
      (Hmem_obs_eq: mem_obs_eq f m m')
      (Hf: f b1 = Some b2)
      (Hfree: Mem.free m b1 0 sz = Some m2)
      (Hfree': Mem.free m' b2 0 sz = Some m2') b0 b3 ofs
      (Hf0: f b0 = Some b3),
      permissions.permission_at m2 b0 ofs Cur =
      permissions.permission_at m2' b3 ofs Cur.
  Proof.
    intros.
    pose proof (injective (weak_obs_eq Hmem_obs_eq)) as Hinjective.
    pose proof (perm_obs_strong (strong_obs_eq Hmem_obs_eq)) as Hperm_eq.
    eapply Mem.free_result in Hfree.
    eapply Mem.free_result in Hfree'.
    subst.
    specialize (Hperm_eq _ _ ofs Hf0).
    unfold permissions.permission_at, Mem.unchecked_free in *. simpl.
    destruct (Pos.eq_dec b0 b1) as [Heq | Hneq].
    - subst.
      assert (b2 = b3)
        by (rewrite Hf0 in Hf; by inv Hf).
      subst b3.
      do 2 rewrite Maps.PMap.gss.
      rewrite Hperm_eq.
      reflexivity.
    - rewrite Maps.PMap.gso; auto.
      rewrite Maps.PMap.gso; auto.
      intros Hcontra.
      subst.
      apply Hneq; eapply Hinjective; eauto.
  Qed.

  Transparent Mem.free.
  
  Lemma mem_free_obs:
    forall f m m' sz b1 b2 m2
      (Hmem_obs_eq: mem_obs_eq f m m')
      (Hf: f b1 = Some b2)
      (Hfree: Mem.free m b1 0 sz = Some m2),
    exists m2',
      Mem.free m' b2 0 sz = Some m2' /\
      mem_obs_eq f m2 m2'.
  Proof.
    intros.
    assert (Hfree': Mem.free m' b2 0 sz = Some (Mem.unchecked_free m' b2 0 sz)).
    { unfold Mem.free.
      destruct (Mem.range_perm_dec m' b2 0 sz Cur Freeable); auto.
      apply Mem.free_range_perm in Hfree.
      unfold Mem.range_perm in *.
      destruct Hmem_obs_eq as [_ [HpermEq _]].
      unfold Mem.perm, permissions.permission_at in *.
      exfalso.
      apply n. intros ofs Hofs.
      specialize (HpermEq _ _ ofs Hf).
      rewrite HpermEq;
        auto.
    } 
    - eexists; split; eauto.
      constructor.
      + (*weak_obs_eq*)
        inversion Hmem_obs_eq as [Hweak_obs_eq Hstrong_obs_eq].
        destruct Hweak_obs_eq.
        assert (Heq_nb := Mem.nextblock_free _ _ _ _ _ Hfree).
        constructor; simpl; unfold Mem.valid_block; try (rewrite Heq_nb);
        auto.
        intros.
        erewrite mem_free_obs_perm with (b1 := b1) (b0 := b0); eauto.
        apply permissions.po_refl.
      + constructor.
        intros.
        erewrite mem_free_obs_perm with (b1 := b1) (b0 := b0); eauto.
      + intros.
        erewrite <- mem_free_contents; eauto.
        erewrite <- mem_free_contents with (m2 := Mem.unchecked_free m' b2 0 sz);
          eauto.
        apply (val_obs_eq (strong_obs_eq Hmem_obs_eq)); auto.
        eapply Mem.perm_free_3; eauto.
  Qed.

  Lemma valid_pointer_ren:
    forall f m m' b1 b2 ofs
      (Hmem_obs_eq: mem_obs_eq f m m')
      (Hf: f b1 = Some b2),
      Mem.valid_pointer m b1 ofs = Mem.valid_pointer m' b2 ofs.
  Proof.
    intros.
    unfold Mem.valid_pointer in *.
    destruct Hmem_obs_eq as [_ [Hperm_eq _]].
    specialize (Hperm_eq _ _ ofs Hf). 
    unfold permissions.permission_at in *.
    unfold Coqlib.proj_sumbool in *.
    destruct (Mem.perm_dec m b1 ofs Cur Nonempty);
      destruct (Mem.perm_dec m' b2 ofs Cur Nonempty); auto.
    unfold Mem.perm in *. rewrite Hperm_eq in n.
      by exfalso.
      unfold Mem.perm in *. rewrite Hperm_eq in p.
        by exfalso.
  Qed.

Lemma val_obs_cmpu:
        forall f v1 v2 v1' v2' m m' (comp : comparison)
          (Hval_obs': val_obs f v2 v2')
          (Hval_obs: val_obs f v1 v1')
          (Hmem_obs_eq: mem_obs_eq f m m'),
          val_obs f (Val.cmpu (Mem.valid_pointer m) comp v1 v2)
                  (Val.cmpu (Mem.valid_pointer m') comp v1' v2').
      Proof with eauto with val_renamings.
        intros.
        destruct v1, v1'; inversion Hval_obs;
        inversion Hval_obs'; subst; simpl; eauto with val_renamings;
        unfold Val.cmpu,Val.of_optbool, Val.cmpu_bool, Vtrue, Vfalse...
        - destruct (Int.cmpu comp i0 i2)...
        - assert (Int.eq i0 Int.zero &&
                       (Mem.valid_pointer m b1 (Int.unsigned ofs)
                        || Mem.valid_pointer m b1 (Int.unsigned ofs - 1))
                = Int.eq i0 Int.zero &&
                         (Mem.valid_pointer m' b2 (Int.unsigned ofs)
                          || Mem.valid_pointer m' b2 (Int.unsigned ofs - 1))).
           { destruct (Int.eq i0 Int.zero); simpl; try reflexivity.
             erewrite valid_pointer_ren; eauto.
             erewrite valid_pointer_ren with (ofs := (Int.unsigned ofs - 1)%Z);
               eauto.
           }
           rewrite H.
        repeat match goal with
               | [|- context[match ?Expr with _ => _ end]] =>
                 destruct Expr eqn:?
               end...
        - assert (Int.eq i1 Int.zero &&
                         (Mem.valid_pointer m b (Int.unsigned i0)
                          || Mem.valid_pointer m b (Int.unsigned i0 - 1))
                = Int.eq i1 Int.zero &&
                         (Mem.valid_pointer m' b0 (Int.unsigned i0)
                          || Mem.valid_pointer m' b0 (Int.unsigned i0 - 1))).
           { destruct (Int.eq i1 Int.zero); simpl; try reflexivity.
             erewrite valid_pointer_ren; eauto.
             erewrite valid_pointer_ren with (ofs := (Int.unsigned i0 - 1)%Z);
               eauto.
           }
           rewrite H.
        repeat match goal with
               | [|- context[match ?Expr with _ => _ end]] =>
                 destruct Expr eqn:?
               end...
        - assert (Hequiv: (eq_block b b3) <-> (eq_block b0 b4)).
          { split.
            - intros Heq.
              destruct (eq_block b b3); subst.
              + rewrite H4 in H0; inversion H0; subst.
                destruct (eq_block b0 b0); auto.
              + by exfalso.
            - intros Heq.
              destruct (eq_block b b3); subst.
              + rewrite H4 in H0; inversion H0; subst.
                destruct (eq_block b0 b0); auto.
              + destruct (eq_block b0 b4); subst; auto.
                assert (Hinjective := injective (weak_obs_eq Hmem_obs_eq)).
                specialize (Hinjective _ _ _ H4 H0); subst.
                  by exfalso.
          }            
          destruct (eq_block b b3) eqn:Hb;
            destruct (eq_block b0 b4) eqn:Hb0; simpl in *; subst;
          destruct Hequiv; try (by exfalso; eauto).
          assert (Hif: (Mem.valid_pointer m b3 (Int.unsigned i0)
                        || Mem.valid_pointer m b3 (Int.unsigned i0 - 1))
                         &&
                         (Mem.valid_pointer m b3 (Int.unsigned ofs0)
                          || Mem.valid_pointer m b3 (Int.unsigned ofs0 - 1))
                       =
                       (Mem.valid_pointer m' b4 (Int.unsigned i0)
                        || Mem.valid_pointer m' b4 (Int.unsigned i0 - 1))
                         &&
                         (Mem.valid_pointer m' b4 (Int.unsigned ofs0)
                          || Mem.valid_pointer m' b4 (Int.unsigned ofs0 - 1))).
          { erewrite valid_pointer_ren; eauto.
            erewrite valid_pointer_ren with
            (m := m) (b1:=b3) (ofs := (Int.unsigned i0 - 1)%Z); eauto.
            erewrite valid_pointer_ren with
            (m := m) (b1:=b3) (ofs := Int.unsigned ofs0); eauto.
            erewrite valid_pointer_ren with
            (m := m) (b1:=b3) (ofs := (Int.unsigned ofs0 - 1)%Z); eauto.
          }
          rewrite Hif.
          repeat match goal with
                 | [|- context[match ?Expr with _ => _ end]] =>
                   destruct Expr eqn:?
                 end...
          erewrite valid_pointer_ren; eauto.
          erewrite valid_pointer_ren with (b1 := b3); eauto.
          repeat match goal with
                 | [|- context[match ?Expr with _ => _ end]] =>
                   destruct Expr eqn:?
                 end...
      Qed.

      Hint Resolve val_obs_cmpu : val_renamings.
      
End MemObsEq.

Import dry_context SEM mySchedule DryMachine DryMachine.ThreadPool.

Module Type CoreInjections.

  Import ValObsEq MemoryWD Renamings MemObsEq.

  Parameter core_wd : memren -> C -> Prop.
  Parameter ge_wd : memren -> G -> Prop.
  
  Parameter ge_wd_incr: forall f f' (g : G),
      ge_wd f g ->
      ren_domain_incr f f' ->
      ge_wd f' g.
  
  Parameter ge_wd_domain : forall f f' m (g : G),
      ge_wd f g ->
      domain_memren f m ->
      domain_memren f' m ->
      ge_wd f' g.
  
  Parameter core_wd_incr : forall f f' c,
      core_wd f c ->
      ren_domain_incr f f' ->
      core_wd f' c.
  
  Parameter core_wd_domain : forall f f' m c,
      core_wd f c ->
      domain_memren f m ->
      domain_memren f' m ->
      core_wd f' c.
  
  Parameter at_external_wd:
    forall f c ef sig args,
      core_wd f c ->
      at_external Sem c = Some (ef, sig, args) ->
      valid_val_list f args.
  
  Parameter after_external_wd:
    forall c c' f ef sig args ov,
      at_external Sem c = Some (ef, sig, args) ->
      core_wd f c ->
      valid_val_list f args ->
      after_external Sem ov c = Some c' ->
      core_wd f c'.
  
  Parameter initial_core_wd:
    forall f vf arg c_new,
      initial_core Sem the_ge vf [:: arg] = Some c_new ->
      valid_val f arg ->
      ge_wd f the_ge ->
      core_wd f c_new.
  
  Parameter core_inj: memren -> C -> C -> Prop.

  Parameter core_inj_ext: 
    forall c c' f (Hinj: core_inj f c c'),
      match at_external Sem c, at_external Sem c' with
      | Some (ef, sig, vs), Some (ef', sig', vs') =>
        ef = ef' /\ sig = sig' /\ val_obs_list f vs vs'
      | None, None => True
      | _, _ => False
      end.
  
  Parameter core_inj_after_ext: 
    forall c cc c' ov1 f (Hinj: core_inj f c c'),
      match ov1 with
      | Some v1 => valid_val f v1
      | None => True
      end ->
      after_external Sem ov1 c = Some cc ->
      exists ov2 cc',
        after_external Sem ov2 c' = Some cc' /\
        core_inj f cc cc' /\
        match ov1 with
        | Some v1 => match ov2 with
                    | Some v2 => val_obs f v1 v2
                    | _ => False
                    end
        | None => match ov2 with
                 | None => True
                 | _ => False
                 end
        end.
  
  Parameter core_inj_halted:
    forall c c' f (Hinj: core_inj f c c'),
      match halted Sem c, halted Sem c' with
      | Some v, Some v' => val_obs f v v'
      | None, None => True
      | _, _ => False
      end.
  
  Parameter core_inj_init:
    forall vf vf' arg arg' c_new f fg
      (Hf: val_obs_list f arg arg')
      (Hf': val_obs f vf vf')
      (Hfg: forall b1 b2, fg b1 = Some b2 -> b1 = b2)
      (Hge_wd: ge_wd fg the_ge)
      (Hincr: ren_incr fg f)
      (Hinit: initial_core Sem the_ge vf arg = Some c_new),
    exists c_new',
      initial_core Sem the_ge vf' arg' = Some c_new' /\
      core_inj f c_new c_new'.
  
  Parameter core_inj_id: forall c f,
      core_wd f c -> 
      (forall b1 b2, f b1 = Some b2 -> b1 = b2) ->
      core_inj f c c.
  
  Parameter core_inj_trans:
    forall c c' c'' (f f' f'' : memren)
      (Hcore_inj: core_inj f c c'')
      (Hcore_inj': core_inj f' c c')
      (Hf: forall b b' b'',
          f b = Some b'' ->
          f' b = Some b' ->
          f'' b' = Some b''),
      core_inj f'' c' c''.

  Parameter corestep_obs_eq:
    forall cc cf cc' mc mf mc' f fg
      (Hobs_eq: mem_obs_eq f mc mf)
      (Hcode_eq: core_inj f cc cf)
      (Hfg: (forall b1 b2, fg b1 = Some b2 -> b1 = b2))
      (Hge_wd: ge_wd fg the_ge)
      (Hincr: ren_incr fg f)
      (Hstep: corestep Sem the_ge cc mc cc' mc'),
    exists cf' mf' f',
      corestep Sem the_ge cf mf cf' mf'
      /\ core_inj f' cc' cf'
      /\ mem_obs_eq f' mc' mf'
      /\ ren_incr f f'
      /\ ren_separated f f' mc mf
      /\ ((exists p, ((Mem.nextblock mc' = Mem.nextblock mc + p)%positive /\
                (Mem.nextblock mf' = Mem.nextblock mf + p)%positive))
         \/ ((Mem.nextblock mc' = Mem.nextblock mc) /\
            (Mem.nextblock mf' = Mem.nextblock mf)))
      /\ (forall b,
            Mem.valid_block mf' b ->
            ~ Mem.valid_block mf b ->
            let bz := ((Zpos b) - ((Zpos (Mem.nextblock mf)) -
                                   (Zpos (Mem.nextblock mc))))%Z in
            f' (Z.to_pos bz) = Some b /\
            f (Z.to_pos bz) = None)
      /\ (Mem.nextblock mc = Mem.nextblock mf ->
         (forall b1 b2, f b1 = Some b2 -> b1 = b2) ->
         forall b1 b2, f' b1 = Some b2 -> b1 = b2).

End CoreInjections.

Module ThreadPoolInjections (CI: CoreInjections).
  
  Import ValObsEq MemoryWD Renamings CI concurrent_machine.
  (** Injections on programs *)

  (*not clear what should happen with vf. Normally it should be in the
genv and hence should be mapped to itself, but let's not expose this
here*)
  Definition ctl_inj f cc cf : Prop :=
    match cc, cf with
    | Kinit vf arg, Kinit vf' arg' =>
      val_obs f vf vf' /\ val_obs f arg arg'
    | Krun c, Krun c' => core_inj f c c'
    | Kblocked c, Kblocked c' => core_inj f c c'
    | Kresume c arg, Kresume c' arg' => core_inj f c c' /\ val_obs f arg arg'
    | _, _  => False
    end.

  (*Again we do not require that the first argument to Kinit is valid
  as we never map it, although maybe we should*)
  Definition ctl_wd f t : Prop :=
    match t with
    | Krun c => core_wd f c
    | Kblocked c => core_wd f c
    | Kresume c v => core_wd f c /\ valid_val f v
    | Kinit vf v => valid_val f vf /\ valid_val f v
    end.

  Lemma ctl_wd_incr : forall f f' c,
      ctl_wd f c ->
      ren_domain_incr f f' ->
      ctl_wd f' c.
  Proof.
    intros f f' c Hwd Hincr.
    destruct c; simpl in *;
    repeat match goal with
           | [H: _ /\ _ |- _] =>
             destruct H
           | [ |- _] => split
           end;     
    try (eapply core_wd_incr; eauto);
    try (eapply valid_val_incr; eauto).
  Qed.
  
  Lemma ctl_inj_trans:
    forall c c' c'' (f f' f'' : memren)
      (Hcore_inj: ctl_inj f c c'')
      (Hcore_inj': ctl_inj f' c c')
      (Hf: forall b b' b'',
          f b = Some b'' ->
          f' b = Some b' ->
          f'' b' = Some b''),
      ctl_inj f'' c' c''.
  Proof.
    intros.
    destruct c, c', c''; simpl in *; try (by exfalso);
    try (destruct Hcore_inj, Hcore_inj'; split);
    try (eapply core_inj_trans; eauto);
    eapply val_obs_trans;
      by eauto.
  Qed.

  Definition tp_wd (f: memren) (tp : thread_pool) : Prop :=
    forall i (cnti: containsThread tp i),
      ctl_wd f (getThreadC cnti).

  Lemma tp_wd_incr : forall f f' tp,
      tp_wd f tp ->
      ren_domain_incr f f' ->
      tp_wd f' tp.
  Proof.
    intros.
    intros i cnti.
    specialize (H i cnti).
    eapply ctl_wd_incr;
      by eauto.
  Qed.

  Lemma ctl_wd_domain:
    forall f f' m (c : ctl),
      ctl_wd f c ->
      domain_memren f m ->
      domain_memren f' m ->
      ctl_wd f' c.
  Proof.
    intros f f' m c Hwd Hf Hf'.
    destruct c; simpl in *;
    repeat match goal with
           | [H: _ /\ _ |- _] => destruct H
           | [|- _ /\ _] => split
           | [|- core_wd _ _] => eapply core_wd_domain; eauto
           | [|- valid_val _ _] => eapply valid_val_domain; eauto
           end.
  Qed.

  Lemma tp_wd_domain:
    forall f f' m (tp : thread_pool),
      tp_wd f tp ->
      domain_memren f m ->
      domain_memren f' m ->
      tp_wd f' tp.
  Proof.
    intros.
    intros i cnti.
    specialize (H i cnti).
    destruct (getThreadC cnti); simpl in *;
    repeat match goal with
           | [H: _ /\ _ |- _] => destruct H
           | [|- _ /\ _] => split
           | [|- core_wd _ _] => eapply core_wd_domain; eauto
           | [|- valid_val _ _] => eapply valid_val_domain; eauto
           end.
  Qed.

  Lemma tp_wd_lockSet:
    forall tp f addr rmap
      (Htp_wd: tp_wd f tp),
      tp_wd f (updLockSet tp addr rmap).
  Proof.
    intros.
    intros i cnti'.
    assert (cnti := cntUpdateL' _ _ cnti').
    specialize (Htp_wd _ cnti).
      by rewrite gLockSetCode.
  Qed.

  Lemma ctl_inj_id:
    forall f c,
      ctl_wd f c ->
      (forall b1 b2, f b1 = Some b2 -> b1 = b2) ->
      ctl_inj f c c.
  Proof.
    intros.
    destruct c; simpl in *;
    repeat match goal with
           |[H: _ /\ _ |- _] =>
            destruct H
           |[|- _ /\ _] => split; auto
           |[|- core_inj _ _ _] =>
            eapply core_inj_id; eauto
           |[|- val_obs _ _ _] =>
            eapply val_obs_id; eauto
           end.
  Qed.

End ThreadPoolInjections.

  