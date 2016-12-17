Require Import Reals.
Require Import List.
Require Import Ensembles.
Require Import Coq.Logic.FunctionalExtensionality.
Require Import Coq.Logic.ProofIrrelevance.
Require Import Coq.Logic.JMeq.
Require Import Coq.Program.Equality.
Require Import Coq.Program.Basics.
Require Import nnr.
Require Export Entropy.
Require Import utils.
Require Import List.

Require Export Autosubst.Autosubst.

Local Open Scope ennr.

Inductive Ty :=
| ℝ : Ty
| Arrow : Ty -> Ty -> Ty
.
Notation "x ~> y" := (Arrow x y) (at level 69, right associativity, y at level 70).

Lemma ty_eq_dec : forall (τ τ' : Ty), {τ = τ'} + {τ <> τ'}.
Proof.
  decide equality.
Defined.

(* u for untyped *)
Inductive u_expr :=
| u_app : u_expr -> u_expr -> u_expr
| u_factor : u_expr -> u_expr
| u_sample : u_expr
| u_plus : u_expr -> u_expr -> u_expr
| u_real : R -> u_expr
| u_lam : Ty -> {bind u_expr} -> u_expr
| u_var : var -> u_expr
.

Definition is_pure (e : u_expr) : Prop :=
  match e with
  | u_real _ | u_lam _ _ | u_var _ => True
  | _ => False
  end.

Instance Ids_u_expr : Ids u_expr. derive. Defined.
Instance Rename_u_expr : Rename u_expr. derive. Defined.
Instance Subst_u_expr : Subst u_expr. derive. Defined.
Instance SubstLemmas_u_expr : SubstLemmas u_expr. derive. Defined.

Definition Env (T : Type) := list T.
Definition empty_env {T : Type} : Env T := nil.
Notation "·" := empty_env.

Fixpoint lookup {T} (ρ : Env T) x : option T :=
  match ρ with
  | nil => None
  | v :: ρ' =>
    match x with
    | O => Some v
    | S x' => lookup ρ' x'
    end
  end.

Inductive expr (Γ : Env Ty) : Ty -> Type :=
| e_real (r : R) : expr Γ ℝ
| e_var {τ : Ty} (x : var)
        (H : lookup Γ x = Some τ)
  : expr Γ τ
| e_lam {τa τr}
        (body : expr (τa :: Γ) τr)
  : expr Γ (τa ~> τr)
| e_app {τa τr}
        (ef : expr Γ (τa ~> τr))
        (ea : expr Γ τa)
  : expr Γ τr
| e_factor (e : expr Γ ℝ)
  : expr Γ ℝ
| e_sample
  : expr Γ ℝ
| e_plus (el : expr Γ ℝ)
         (er : expr Γ ℝ)
  : expr Γ ℝ.

Arguments e_real {Γ} r.
Arguments e_var {Γ τ} x H.
Arguments e_lam {Γ τa τr} body.
Arguments e_app {Γ τa τr} ef ea.
Arguments e_factor {Γ} e.
Arguments e_sample {Γ}.
Arguments e_plus {Γ} el er.

Fixpoint erase {Γ τ} (e : expr Γ τ) : u_expr :=
  match e with
  | e_real r => u_real r
  | e_var x _ => u_var x
  | @e_lam _ τa τr body => u_lam τa (erase body)
  | e_app ef ea => u_app (erase ef) (erase ea)
  | e_factor e => u_factor (erase e)
  | e_sample => u_sample
  | e_plus el er => u_plus (erase el) (erase er)
  end.
Coercion erase' {Γ τ} : expr Γ τ -> u_expr := erase.
Arguments erase' / {_ _} _.

Lemma expr_type_unique {Γ τ0 τ1} (e0 : expr Γ τ0) (e1 : expr Γ τ1) :
  erase e0 = erase e1 ->
  τ0 = τ1.
Proof.
  intros Heq.
  revert τ1 e1 Heq.
  dependent induction e0; intros;
    dependent destruction e1;
    inversion Heq; subst;
    auto.
  {
    clear Heq.
    rewrite H0 in H.
    inversion H.
    auto.
  } {
    f_equal.
    eapply IHe0.
    eauto.
  } {
    specialize (IHe0_1 _ _ H0).
    inversion IHe0_1.
    auto.
  }
Qed.

Require Import FinFun.
Lemma erase_injective Γ τ : Injective (@erase Γ τ).
Proof.
  intro x.
  dependent induction x;
    intros y Hxy;
    dependent destruction y;
    inversion Hxy; subst; auto.
  {
    f_equal.
    apply UIP_dec.
    decide equality.
    apply ty_eq_dec.
  } {
    f_equal.
    apply IHx; auto.
  } {
    pose proof expr_type_unique x1 y1 H0.
    inversion H; subst.
    erewrite IHx1; eauto.
    erewrite IHx2; eauto.
  } {
    f_equal.
    apply IHx; auto.
  } {
    erewrite IHx1; eauto.
    erewrite IHx2; eauto.
  }
Qed.
Arguments erase_injective {_ _ _ _} _.

Ltac inject_erase_directly :=
  match goal with
  | [ H : erase ?x = erase ?y |- _ ] =>
    apply erase_injective in H;
    try subst x
  end.

Ltac match_erase_eqs :=
  let H := fresh "H" in
  let H' := fresh "H" in
  match goal with
  | [H0 : erase ?x = ?s, H1 : erase ?y = ?s |- _ ] =>
    pose proof (eq_trans H0 (eq_sym H1)) as H;
    let z := type of y in
    match type of x with
    | z => idtac
    | expr · ?τ =>
      pose proof (expr_type_unique _ _ H) as H';
      (subst τ || d_destruct H')
    end;
    apply erase_injective in H;
    subst x
  end;
  clear_dups.

Ltac subst_erase_eq :=
  match goal with
  | [ H : erase ?e = _, H' : context [ erase ?e ] |- _ ] =>
    rewrite H in H';
      try clear H e
  end.

(* d_destruct is often slow, do don't use unless we need *)
(* TODO: speed up even more for exprs *)
Ltac expr_destruct e :=
  match type of e with
  | expr _ (_ ~> _) => d_destruct e
  | expr _ ℝ => d_destruct e
  | expr _ _ => destruct e
  end.

Ltac inject_erased :=
  let go e H :=
      expr_destruct e; inject H
  in match goal with
     | [ H : erase ?e = u_app _ _ |- _ ] => go e H
     | [ H : erase ?e = u_factor _ |- _ ] => go e H
     | [ H : erase ?e = u_sample |- _ ] => go e H
     | [ H : erase ?e = u_plus _ _ |- _ ] => go e H
     | [ H : erase ?e = u_real _ |- _ ] => go e H
     | [ H : erase ?e = u_lam _ _ |- _ ] => go e H
     | [ H : erase ?e = u_var _ |- _ ] => go e H
     end.


Ltac elim_erase_eqs :=
  progress repeat (subst_erase_eq
                   || inject_erase_directly
                   || match_erase_eqs
                   || inject_erased);
  clear_dups.

Ltac elim_sig_exprs :=
  let doit Γ τ pair stac :=
      (let e := fresh "e" in
       let He := fresh "H" e in
       destruct pair as [e He];
       stac;
       asimpl in He) in
  progress repeat
           match goal with
           | [ H : context [ @proj1_sig (expr ?Γ ?τ) _ ?pair ] |- _ ] =>
             doit Γ τ pair ltac:(simpl in H)
           | [ |- context [ @proj1_sig (expr ?Γ ?τ) _ ?pair ] ] =>
             doit Γ τ pair ltac:simpl
           end.
Definition is_val (e : u_expr) : Prop :=
  match e with
  | u_real _ | u_lam _ _ => True
  | _ => False
  end.

Lemma is_val_unique {e : u_expr} (iv0 iv1 : is_val e) :
  iv0 = iv1.
Proof.
  destruct e; try contradiction; destruct iv0, iv1; auto.
Qed.

Inductive val τ :=
  mk_val (e : expr · τ) (H : is_val e).
Arguments mk_val {τ} e H.
Coercion expr_of_val {τ} : val τ -> expr · τ :=
  fun v => let (e, _) := v in e.

Lemma val_eq {τ} {v0 v1 : val τ} :
  @eq (expr · τ) v0 v1 ->
  @eq (val τ) v0 v1.
Proof.
  intros.
  destruct v0, v1.
  cbn in *.
  subst.
  rewrite (is_val_unique H0 H1).
  auto.
Qed.

Definition v_real r : val ℝ :=
  mk_val (e_real r) I.

Definition v_lam {τa τr} body : val (τa ~> τr) :=
  mk_val (e_lam body) I.

Definition rewrite_v_real r : e_real r = v_real r := eq_refl.
Definition rewrite_v_lam {τa τr} body : e_lam body = @v_lam τa τr body := eq_refl.

Lemma val_arrow_rect {τa τr}
      (P : val (τa ~> τr) -> Type)
      (case_lam : forall body, P (v_lam body)) :
  forall v, P v.
Proof.
  intros.
  destruct v as [v Hv].
  dependent destruction v; try contradiction Hv.
  destruct Hv.
  apply case_lam.
Defined.

Lemma val_real_rect
      (P : val ℝ -> Type)
      (case_real : forall r, P (v_real r)) :
  forall v, P v.
Proof.
  intros.
  destruct v as [v Hv].
  dependent destruction v; try contradiction Hv.
  destruct Hv.
  apply case_real.
Defined.

Lemma wt_val_rect {τ}
      (P : val τ -> Type)
      (case_real :
         forall r (τeq : ℝ = τ),
           P (rew τeq in v_real r))
      (case_lam :
         forall τa τr
                (τeq : (τa ~> τr) = τ)
                body,
           P (rew τeq in v_lam body)) :
  forall v, P v.
Proof.
  intros.
  destruct τ. {
    apply val_real_rect.
    intros.
    exact (case_real r eq_refl).
  } {
    apply val_arrow_rect.
    intros.
    exact (case_lam _ _ eq_refl body).
  }
Qed.

Ltac destruct_val wt_v :=
  match (type of wt_v) with
  | val ℝ =>
    destruct wt_v using val_real_rect
  | val (?τa ~> ?τr) =>
    destruct wt_v using val_arrow_rect
  | val ?τ =>
    destruct wt_v using wt_val_rect
  end.

Lemma for_absurd_val {τ} {v : val τ} {e : expr · τ} :
  (expr_of_val v) = e ->
  is_val e.
Proof.
  intros.
  destruct v.
  subst.
  auto.
Qed.

Ltac absurd_val :=
  match goal with
  | [ H : (expr_of_val _) = _ |- _ ] =>
    contradiction (for_absurd_val H)
  | [ H : _ = (expr_of_val _) |- _ ] =>
    contradiction (for_absurd_val (eq_sym H))
  end.

Inductive dep_env {A} (v : A -> Type) : Env A -> Type :=
| dep_nil : dep_env v ·
| dep_cons {τ Γ'} : v τ -> dep_env v Γ' -> dep_env v (τ :: Γ')
.
Arguments dep_nil {_ _}.
Arguments dep_cons {_ _ _ _} _ _.

Fixpoint dep_lookup {A} {v : A -> Type} {Γ} (ρ : dep_env v Γ) (x : nat)
  : option {τ : A & v τ} :=
  match ρ with
  | dep_nil => None
  | dep_cons e ρ' =>
    match x with
    | O => Some (existT _ _ e)
    | S x' => dep_lookup ρ' x'
    end
  end.

Fixpoint dep_env_map {A} {v0 v1 : A -> Type} {Γ}
         (f : forall a, v0 a -> v1 a)
         (ρ : dep_env v0 Γ)
  : dep_env v1 Γ :=
  match ρ with
  | dep_nil => dep_nil
  | dep_cons e ρ' => dep_cons (f _ e) (dep_env_map f ρ')
  end.

Fixpoint dep_env_all {A} {v : A -> Type} {Γ}
         (P : forall a, v a -> Prop)
         (ρ : dep_env v Γ) : Prop
  :=
    match ρ with
    | dep_nil => True
    | dep_cons e ρ' => P _ e /\ dep_env_all P ρ'
    end.

Fixpoint dep_env_allT {A} {v : A -> Type} {Γ}
         (P : forall a, v a -> Type)
         (ρ : dep_env v Γ) : Type
  :=
    match ρ with
    | dep_nil => True
    | dep_cons e ρ' => P _ e ⨉ dep_env_allT P ρ'
    end.

Definition wt_env := dep_env val.

Fixpoint erase_wt_expr_env {Γ Δ} (ρ : dep_env (expr Δ) Γ)
  : (nat -> u_expr) :=
  match ρ with
  | dep_nil => ids
  | dep_cons e ρ' => erase e .: erase_wt_expr_env ρ'
  end.

Fixpoint erase_wt_env {Γ} (ρ : wt_env Γ) : nat -> u_expr :=
  match ρ with
  | dep_nil => ids
  | dep_cons e ρ' => erase e .: erase_wt_env ρ'
  end.

Lemma erase_envs_equiv {Γ} (ρ : wt_env Γ) :
  erase_wt_expr_env (dep_env_map (@expr_of_val) ρ) =
  erase_wt_env ρ.
Proof.
  induction ρ; simpl; auto.
  f_equal.
  auto.
Qed.

(* borrowed from a comment in autosubst, hope it's right *)
Fixpoint sapp {X : Type} (l : list X) (sigma : nat -> X) : nat -> X :=
  match l with nil => sigma | cons s l' => s .: sapp l' sigma end.
Infix ".++" := sapp (at level 55, right associativity) : subst_scope.
Arguments sapp {_} !l sigma / _.

(* Definition subst_of_WT_Env {Γ} (ρ : WT_Env Γ) : nat -> Expr := *)
(*   sapp (downgrade_env ρ) ids. *)

(* Lemma subst_of_WT_Env_lookup {Γ x v} {ρ : WT_Env Γ} : *)
(*   (lookup ρ x = Some v) -> *)
(*   subst_of_WT_Env ρ x = v. *)
(* Proof. *)
(*   intros. *)
(*   unfold subst_of_WT_Env. *)
(*   destruct ρ as [ρ]. *)
(*   simpl in *. *)
(*   clear WT_Env_tc0. *)
(*   revert ρ H. *)
(*   induction x; intros. { *)
(*     destruct ρ; try discriminate. *)
(*     inversion H. *)
(*     autosubst. *)
(*   } { *)
(*     destruct ρ; try discriminate. *)
(*     apply IHx. *)
(*     auto. *)
(*   } *)
(* Qed. *)

Definition env_search {A Γ} {v : A -> Type} (ρ : dep_env v Γ) {x τ} :
  lookup Γ x = Some τ ->
  {e : v τ | dep_lookup ρ x = Some (existT v τ e)}.
Proof.
  intros.
  revert Γ ρ H.
  induction x; intros. {
    destruct Γ; inversion H; subst.
    dependent destruction ρ.
    eexists.
    reflexivity.
  } {
    destruct Γ; try solve [inversion H]; subst.
    dependent destruction ρ.
    simpl in *.
    exact (IHx _ _ H).
  }
Qed.

Lemma lookup_subst {Γ x τ v} (ρ : wt_env Γ) :
  dep_lookup ρ x = Some (existT val τ v) ->
  erase v = erase_wt_env ρ x.
Proof.
  revert Γ ρ.
  induction x; intros. {
    destruct ρ; inversion H; subst.
    dependent destruction H2.
    auto.
  } {
    destruct ρ; inversion H; subst.
    simpl.
    apply IHx.
    auto.
  }
Qed.

Lemma weaken_lookup {A} {Γ : Env A} {x τ Γw} :
  lookup Γ x = Some τ ->
  lookup (Γ ++ Γw) x = Some τ.
Proof.
  intros.
  revert Γ H.
  induction x; intros. {
    destruct Γ; inversion H.
    auto.
  } {
    destruct Γ; try discriminate H.
    simpl in *.
    apply IHx.
    auto.
  }
Qed.

Fixpoint weaken {Γ τ} (e : expr Γ τ) Γw : expr (Γ ++ Γw) τ :=
  match e with
  | e_real r => e_real r
  | e_var x H => e_var x (weaken_lookup H)
  | e_lam body => e_lam (weaken body Γw)
  | e_app ef ea => e_app (weaken ef Γw) (weaken ea Γw)
  | e_factor e => e_factor (weaken e Γw)
  | e_sample => e_sample
  | e_plus el er => e_plus (weaken el Γw) (weaken er Γw)
  end.

Lemma weaken_eq {Γ τ} (e : expr Γ τ) Γw :
  erase e = erase (weaken e Γw).
Proof.
  induction e; simpl; f_equal; auto.
Qed.

Lemma expr_ren {Γ τ} ξ (e : expr Γ τ) Δ :
  lookup Γ = ξ >>> lookup Δ ->
  {e' : expr Δ τ |
   erase e' = rename ξ (erase e)}.
Proof.
  revert ξ Δ.
  induction e; intros. {
    exists (e_real r).
    simpl.
    auto.
  } {
    simple refine (exist _ (e_var (ξ x) _) _); simpl; auto.
    rewrite <- H.
    rewrite H0.
    auto.
  } {
    assert (lookup (τa :: Γ) = upren ξ >>> lookup (τa :: Δ)). {
      extensionality x.
      destruct x; auto.
      simpl.
      rewrite H.
      auto.
    }
    destruct (IHe _ _ H0).
    exists (e_lam x).
    simpl.
    rewrite e0.
    auto.
  } {
    edestruct IHe1, IHe2; eauto.
    eexists (e_app _ _).
    simpl.
    rewrite e, e0.
    auto.
  } {
    edestruct IHe; eauto.
    eexists (e_factor _).
    simpl.
    rewrite e0.
    auto.
  } {
    exists e_sample; auto.
  } {
    edestruct IHe1, IHe2; eauto.
    eexists (e_plus _ _).
    simpl.
    rewrite e, e0.
    auto.
  }
Qed.

Lemma up_inj : Injective up.
  intros ? ? ?.
  assert (forall z, up x z = up y z). {
    rewrite H.
    auto.
  }
  extensionality z.
  specialize (H0 (S z)).
  unfold up in H0.
  simpl in H0.
  set (x z) in *.
  set (y z) in *.
  set (+1)%nat in *.
  assert (Injective v). {
    intros ? ? ?.
    subst v.
    inversion H; auto.
  }
  clearbody v u u0.
  revert u0 v H0 H1.
  clear.
  induction u; intros; destruct u0; inversion H0; f_equal; eauto. {
    eapply IHu; eauto.
    repeat intro.
    revert H1 H; clear; intros.
    compute in H.
    destruct x, y; auto; discriminate H.
  }
Qed.

Lemma up_expr_env {Γ Δ : Env Ty}
      (σ : dep_env (expr Δ) Γ)
      (τa : Ty)
  : { σ' : dep_env (expr (τa :: Δ)) (τa :: Γ) |
      forall x τ,
        lookup (τa :: Γ) x = Some τ ->
        erase_wt_expr_env σ' x = up (erase_wt_expr_env σ) x }.
Proof.
  simple refine (exist _ _ _); auto. {
    constructor. {
      apply (e_var O).
      auto.
    } {
      refine (dep_env_map _ σ).
      intros a e.
      apply (expr_ren S e).
      auto.
    }
  } {
    simpl.
    intros.
    revert Γ Δ σ H.
    destruct x; auto.
    induction x; intros. {
      simpl.
      destruct σ; inversion H; subst.
      simpl.
      destruct expr_ren.
      rewrite e0.
      auto.
    } {
      destruct σ; try discriminate H; simpl in *.
      rewrite IHx; auto.
    }
  }
Qed.

Lemma subst_only_matters_up_to_env {Γ τ} (e : expr Γ τ) σ0 σ1 :
  (forall x τ,
      lookup Γ x = Some τ ->
      σ0 x = σ1 x) ->
  (erase e).[σ0] = (erase e).[σ1].
Proof.
  revert σ0 σ1.
  induction e; simpl; intros; f_equal; eauto.

  apply IHe.
  intros.
  destruct x; auto.
  simpl in H0.
  specialize (H _ _ H0).
  unfold up.
  simpl.
  rewrite H.
  auto.
Qed.

Lemma ty_subst {Γ τ} (e : expr Γ τ) :
  forall Δ (ρ : dep_env (expr Δ) Γ),
    {e' : expr Δ τ |
     erase e' = (erase e).[erase_wt_expr_env ρ]}.
Proof.
  induction e; intros. {
    exists (e_real r).
    reflexivity.
  } {
    simpl.
    destruct (env_search ρ H).
    exists x0.
    revert Γ H ρ e.
    induction x; intros. {
      destruct ρ; inversion e; subst.
      auto.
    } {
      destruct ρ; inversion e; subst.
      simpl.
      apply IHx; auto.
    }
  } {
    destruct (up_expr_env ρ τa).
    destruct (IHe _ x).

    eexists (e_lam _).
    simpl.
    f_equal.
    rewrite e1.

    apply subst_only_matters_up_to_env.
    auto.
  } {
    edestruct IHe1, IHe2; auto.
    eexists (e_app _ _).
    simpl.
    rewrite e, e0.
    reflexivity.
  } {
    edestruct IHe; auto.
    exists (e_factor x).
    simpl.
    rewrite e0.
    reflexivity.
  } {
    exists e_sample.
    reflexivity.
  } {
    edestruct IHe1, IHe2; auto.
    exists (e_plus x x0).
    simpl.
    rewrite e, e0.
    reflexivity.
  }
Qed.

Lemma close {Γ} (ρ : wt_env Γ) {τ} (e : expr Γ τ) :
  {e' : expr · τ |
   erase e' = (erase e).[erase_wt_env ρ]}.
Proof.
  rewrite <- erase_envs_equiv.
  apply ty_subst.
Qed.

Definition ty_subst1 {τa τr}
      (e : expr (τa :: ·) τr)
      (v : val τa) :
  { e' : expr · τr |
    erase e' = (erase e).[erase v /] }
  := ty_subst e · (dep_cons (v : expr · τa) dep_nil).

Lemma body_subst {Γ τa τr} (ρ : wt_env Γ)
      (body : expr (τa :: Γ) τr) :
  { body' : expr (τa :: ·) τr |
    erase body' = (erase body).[up (erase_wt_env ρ)] }.
Proof.
  pose proof ty_subst body (τa :: ·).

  destruct (up_expr_env (dep_env_map (@expr_of_val) ρ) τa).
  destruct (X x).
  exists x0.
  rewrite e0.
  apply subst_only_matters_up_to_env.
  intros.
  erewrite e; eauto.
  rewrite erase_envs_equiv.
  auto.
Qed.

Reserved Notation "'EVAL' σ ⊢ e ⇓ v , w" (at level 69, e at level 99, no associativity).
Inductive eval (σ : Entropy) : forall {τ} (e : expr · τ) (v : val τ) (w : R+), Type :=
| EPure {τ} (v : val τ) :
    (EVAL σ ⊢ v ⇓ v, 1)
| EApp {τa τr}
       {ef : expr · (τa ~> τr)}
       {ea : expr · τa}
       {body : expr (τa :: ·) τr}
       {va : val τa}
       {vr : val τr}
       {w0 w1 w2 : R+}
  : (EVAL (π 0 σ) ⊢ ef ⇓ mk_val (e_lam body) I, w0) ->
    (EVAL (π 1 σ) ⊢ ea ⇓ va, w1) ->
    (EVAL (π 2 σ) ⊢ proj1_sig (ty_subst1 body va) ⇓ vr, w2) ->
    (EVAL σ ⊢ e_app ef ea ⇓ vr, w0 * w1 * w2)
| EFactor {e : expr · ℝ} {r : R} {w : R+} {is_v} (rpos : (0 <= r)%R)
  : (EVAL σ ⊢ e ⇓ mk_val (e_real r) is_v, w) ->
    (EVAL σ ⊢ e_factor e ⇓ v_real r, finite r rpos * w)
| ESample
  : (EVAL σ ⊢ e_sample ⇓ v_real (proj1_sig (σ O)), 1)
| EPlus {e0 e1 : expr · ℝ} {r0 r1 : R} {is_v0 is_v1} {w0 w1 : R+}
  : (EVAL (π 0 σ) ⊢ e0 ⇓ mk_val (e_real r0) is_v0, w0) ->
    (EVAL (π 1 σ) ⊢ e1 ⇓ mk_val (e_real r1) is_v1, w1) ->
    (EVAL σ ⊢ e_plus e0 e1 ⇓ v_real (r0 + r1), w0 * w1)
where "'EVAL' σ ⊢ e ⇓ v , w" := (@eval σ _ e v w)
.

Definition EPure' (σ : Entropy) {τ} (e : expr · τ) (v : val τ) :
  e = v ->
  (EVAL σ ⊢ e ⇓ v, 1).
Proof.
  intros.
  rewrite H.
  constructor.
Qed.

Lemma invert_eval_val {σ τ} {v v' : val τ} {w} :
  (EVAL σ ⊢ v ⇓ v', w) ->
  v = v' /\ w = 1.
Proof.
  intros.
  destruct τ;
    destruct_val v;
    destruct_val v';
    dependent destruction H;
    auto.
Qed.

Lemma u_expr_eq_dec (u0 u1 : u_expr) :
  {u0 = u1} + {u0 <> u1}.
Proof.
  decide equality. {
    apply Req_EM_T.
  } {
    decide equality.
  } {
    decide equality.
  }
Qed.

Lemma expr_eq_dec {Γ τ} (e0 e1 : expr Γ τ) :
  {e0 = e1} + {e0 <> e1}.
Proof.
  destruct (u_expr_eq_dec (erase e0) (erase e1)). {
    left.
    elim_erase_eqs.
    auto.
  } {
    right.
    intro.
    subst.
    auto.
  }
Qed.