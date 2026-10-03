/* Copyright (C) 2013  Olga Yakovleva <yakovleva.o.v@gmail.com> */

/* This program is free software: you can redistribute it and/or modify */
/* it under the terms of the GNU Lesser General Public License as published by */
/* the Free Software Foundation, either version 2.1 of the License, or */
/* (at your option) any later version. */

/* This program is distributed in the hope that it will be useful, */
/* but WITHOUT ANY WARRANTY; without even the implied warranty of */
/* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the */
/* GNU Lesser General Public License for more details. */

/* You should have received a copy of the GNU Lesser General Public License */
/* along with this program.  If not, see <https://www.gnu.org/licenses/>. */

%include {#include "core/userdict.hpp"}

%name userdictParse

%start_symbol line

%token_prefix UDTK_
%token_type {ElnurTTS::userdict::token*}
%token_destructor {delete $$;}

%type rule {ElnurTTS::userdict::ruleset*}
%destructor rule {delete $$;}
%type collocation_rule {ElnurTTS::userdict::ruleset*}
%destructor collocation_rule {delete $$;}
%type symbol_rule {ElnurTTS::userdict::ruleset*}
%destructor symbol_rule {delete $$;}
%type tokens {ElnurTTS::userdict::ruleset*}
%destructor tokens {delete $$;}
%type prefix {ElnurTTS::userdict::ruleset*}
%destructor prefix {delete $$;}
%type suffix {ElnurTTS::userdict::ruleset*}
%destructor suffix {delete $$;}
%type token {ElnurTTS::userdict::ruleset*}
%destructor token {delete $$;}
%type words {ElnurTTS::userdict::ruleset*}
%destructor words {delete $$;}
%type word {ElnurTTS::userdict::ruleset*}
%destructor word {delete $$;}
%type inline_rewrites {ElnurTTS::userdict::ruleset*}
%destructor inline_rewrites {delete $$;}
%type inline_rewrite {ElnurTTS::userdict::ruleset*}
%destructor inline_rewrite {delete $$;}
%type inline_replacement {ElnurTTS::userdict::ruleset*}
%destructor inline_replacement {delete $$;}
%type word_flags {ElnurTTS::userdict::ruleset*}
%destructor word_flags {delete $$;}
%type token_pron {ElnurTTS::userdict::ruleset*}
%destructor token_pron {delete $$;}
%type symbol_pron {ElnurTTS::userdict::ruleset*}
%destructor symbol_pron {delete $$;}
%type spaced_symbol_pron {ElnurTTS::userdict::ruleset*}
%destructor spaced_symbol_pron {delete $$;}
%type word_pron {ElnurTTS::userdict::ruleset*}
%destructor word_pron {delete $$;}
%type pron_repr {ElnurTTS::userdict::ruleset*}
%destructor pron_repr {delete $$;}
%type text_pron_repr {ElnurTTS::userdict::ruleset*}
%destructor text_pron_repr {delete $$;}
%type text_pron_repr_atom {ElnurTTS::userdict::ruleset*}
%destructor text_pron_repr_atom {delete $$;}
%type word_pron_flags {ElnurTTS::userdict::ruleset*}
%destructor word_pron_flags {delete $$;}
%type set {ElnurTTS::userdict::ruleset*}
%destructor set {delete $$;}
%type set_elements {ElnurTTS::userdict::ruleset*}
%destructor set_elements {delete $$;}
%type set_element {ElnurTTS::userdict::ruleset*}
%destructor set_element {delete $$;}
%type pattern {ElnurTTS::userdict::ruleset*}
%destructor pattern {delete $$;}
%type subpattern {ElnurTTS::userdict::ruleset*}
%destructor subpattern {delete $$;}
%type substring {ElnurTTS::userdict::ruleset*}
%destructor substring {delete $$;}
%type symbol {ElnurTTS::userdict::ruleset*}
%destructor symbol {delete $$;}
%type insertion {ElnurTTS::userdict::ruleset*}
%destructor insertion {delete $$;}
%type deletion {ElnurTTS::userdict::ruleset*}
%destructor deletion {delete $$;}
%type stress_mark {ElnurTTS::userdict::ruleset*}
%destructor stress_mark {delete $$;}
%type stressed_syl_number {ElnurTTS::userdict::ruleset*}
%destructor stressed_syl_number {delete $$;}
%type stressed_syl_numbers {ElnurTTS::userdict::ruleset*}
%destructor stressed_syl_numbers {delete $$;}
%type unstressed_flag {ElnurTTS::userdict::ruleset*}
%destructor unstressed_flag {delete $$;}
%type initialism_flag {ElnurTTS::userdict::ruleset*}
%destructor initialism_flag {delete $$;}

%extra_argument {ElnurTTS::userdict::parse_state* ps}

%syntax_error {ps->error=true;}

line ::= rule(X) NEWLINE.
{
  if(!ps->error) ps->result->extend(X);
  delete X;
}

line ::= NEWLINE.

rule(X) ::= collocation_rule(Y).
{
  X=Y;
}

rule(X) ::= symbol_rule(Y).
{
  X=Y;
}

collocation_rule(X) ::= prefix(U) tokens(V) suffix(W).
{
  X=U;
  X->append(V);
  X->append(W);
  delete V;
  delete W;
}

symbol_rule(X) ::= symbol(Y) space EQUALS space symbol_pron(Z).
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::start_of_token>();
  X->append(Y);
  X->append(Z);
  X->append<ElnurTTS::userdict::end_of_token>();
  delete Y;
  delete Z;
}

tokens(X) ::= tokens(Y) SPACE token(Z).
{
  X=Y;
  X->append<ElnurTTS::userdict::end_of_token>();
  X->append<ElnurTTS::userdict::start_of_token>();
  X->append(Z);
  delete Z;
}

tokens(X) ::= token(Y).
{
  X=Y;
}

prefix(X) ::= STAR.
{
  X=new ElnurTTS::userdict::ruleset;
}

prefix(X) ::= .
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::start_of_token>();
}

suffix(X) ::= STAR.
{
  X=new ElnurTTS::userdict::ruleset;
}

suffix(X) ::= .
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::end_of_token>();
}

token(X) ::= words(Y).
{
  X=Y;
}

token(X) ::= deletion(Y) EQUALS token_pron(Z).
{
  X=Y;
  X->append(Z);
  delete Z;
}

words(X) ::= words(Y) AND word(Z).
{
  X=Y;
  X->append<ElnurTTS::userdict::word_break>();
  X->append(Z);
  delete Z;
}

words(X) ::= word(Y).
{
  X=Y;
}

word(X) ::= inline_rewrites(Y) word_flags(Z).
{
  X=Y;
  X->append(Z);
  delete Z;
}

inline_rewrites(X) ::= inline_rewrites(Y) inline_rewrite(Z).
{
  X=Y;
  X->append(Z);
  delete Z;
}

inline_rewrites(X) ::= inline_rewrite(Y).
{
  X=Y;
}

inline_rewrite(X) ::= inline_replacement(Y).
{
  X=Y;
}

inline_rewrite(X) ::= subpattern(Y).
{
  X=Y;
}

inline_rewrite(X) ::= stress_mark(Y).
{
  X=Y;
}

inline_replacement(X) ::= LPAREN deletion(Y) EQUALS text_pron_repr(Z) RPAREN.
{
  X=Y;
  X->append(Z);
  delete Z;
}

word_flags(X) ::= .
{
  X=new ElnurTTS::userdict::ruleset;
}

word_flags(X) ::= stressed_syl_numbers(Y).
{
  X=Y;
}

word_flags(X) ::= unstressed_flag(Y).
{
  X=Y;
}

word_flags(X) ::= initialism_flag(Y).
{
  X=Y;
}

set(X) ::= LBRACE set_elements(Y) RBRACE.
{
  X=Y;
}

set_elements(X) ::= set_elements(Y) COMMA set_element(Z).
{
  X=Y;
  X->extend(Z);
  delete Z;
}

set_elements(X) ::= set_element(Y).
{
  X=Y;
}

set_element(X) ::= pattern(Y).
{
  X=Y;
}

set_element(X) ::= .
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::empty_string>();
}

pattern(X) ::= pattern(Y) subpattern(Z).
{
  X=Y;
  X->append(Z);
  delete Z;
}

pattern(X) ::= subpattern(Y).
{
  X=Y;
}

subpattern(X) ::= substring(Y).
{
  X=Y;
}

subpattern(X) ::= set(Y).
{
  X=Y;
}

symbol_pron(X) ::= spaced_symbol_pron(Y).
{
  X=Y;
}

symbol_pron(X) ::=  token_pron(Y).
{
  X=Y;
}

token_pron(X) ::= token_pron(Y) AND word_pron(Z).
{
  X=Y;
  X->append<ElnurTTS::userdict::word_break>();
  X->append(Z);
  delete Z;
}

token_pron(X) ::= word_pron(Y).
{
  X=Y;
}

spaced_symbol_pron(X) ::= spaced_symbol_pron(Y) SPACE word_pron(Z).
{
  X=Y;
  X->append<ElnurTTS::userdict::word_break>();
  X->append(Z);
  delete Z;
}

spaced_symbol_pron(X) ::= word_pron(Y) SPACE word_pron(Z).
{
  X=Y;
  X->append<ElnurTTS::userdict::word_break>();
  X->append(Z);
  delete Z;
}

word_pron(X) ::= pron_repr(Y) word_pron_flags(Z).
{
  X=Y;
  X->append(Z);
  delete Z;
}

pron_repr(X) ::= text_pron_repr(Y).
{
  X=Y;
}

word_pron_flags(X) ::= .
{
  X= new ElnurTTS::userdict::ruleset;
}

word_pron_flags(X) ::= stressed_syl_numbers(Y).
{
  X=Y;
}

word_pron_flags(X) ::= unstressed_flag(Y).
{
  X=Y;
}

text_pron_repr(X) ::= text_pron_repr(Y) text_pron_repr_atom(Z).
{
  X=Y;
  X->append(Z);
  delete Z;
}

text_pron_repr(X) ::= text_pron_repr_atom(Y).
{
  X=Y;
}

text_pron_repr_atom(X)::= insertion(Y).
{
  X=Y;
}

text_pron_repr_atom(X) ::= stress_mark(Y).
{
  X=Y;
}

substring(X) ::= NATIVE_LETTERS(Y).
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::substring>(Y);
  delete Y;
}

substring(X) ::= ENGLISH_LETTERS(Y).
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::substring>(Y);
  delete Y;
}

symbol(X) ::= SYM(Y).
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::symbol>(Y);
  delete Y;
}

deletion(X) ::= NATIVE_LETTERS(Y).
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::deletion>(Y);
  delete Y;
}

deletion(X) ::= ENGLISH_LETTERS(Y).
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::deletion>(Y);
  delete Y;
}

insertion(X) ::= NATIVE_LETTERS(Y).
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::insertion>(Y);
  delete Y;
}

stress_mark(X) ::= PLUS.
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::stress_mark>();
}

stressed_syl_numbers(X) ::= stressed_syl_numbers(Y) stressed_syl_number(Z).
{
  X=Y;
  X->append(Z);
  delete Z;
}

stressed_syl_numbers(X) ::= stressed_syl_number(Y).
{
  X=Y;
}

stressed_syl_number(X) ::= STRESSED_SYL_NUMBER(Y).
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::stressed_syl_number>(Y);
  delete Y;
}

unstressed_flag(X) ::= UNSTRESSED.
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::unstressed_flag>();
}

initialism_flag(X) ::= INITIALISM.
{
  X=ElnurTTS::userdict::ruleset::create<ElnurTTS::userdict::initialism_flag>();
}

space ::= . space ::= SPACE.

// Local Variables:
// mode: lemon-c++
// End:
