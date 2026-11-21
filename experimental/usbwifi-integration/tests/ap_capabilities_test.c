/* SPDX-License-Identifier: MIT-0 */
#define main capability_program_main
#include "ap-capabilities.c"
#undef main
#include <assert.h>
static unsigned char fixture[512];
static int used;
static int open_attr(int type) {
    int p=used; struct nlattr *a=(void *)(fixture+p);
    a->nla_type=type; a->nla_len=sizeof(*a); used+=sizeof(*a); return p;
}
static void close_attr(int p) { ((struct nlattr *)(fixture+p))->nla_len=used-p; }
static void flag(int type) { close_attr(open_attr(type)); }
static void make_fixture(int has_ap,int disabled,int no_ir,unsigned freq) {
    memset(fixture,0,sizeof(fixture)); used=ap=channel=got_types=got_bands=0;
    int types=open_attr(NL80211_ATTR_SUPPORTED_IFTYPES);
    flag(has_ap?NL80211_IFTYPE_AP:NL80211_IFTYPE_STATION); close_attr(types);
    int bands_at=open_attr(NL80211_ATTR_WIPHY_BANDS), band=open_attr(1);
    int freqs=open_attr(NL80211_BAND_ATTR_FREQS), f=open_attr(1);
    int n=open_attr(NL80211_FREQUENCY_ATTR_FREQ);
    memcpy(fixture+used,&freq,4); used+=4; close_attr(n);
    if(disabled) flag(NL80211_FREQUENCY_ATTR_DISABLED);
    if(no_ir) flag(NL80211_FREQUENCY_ATTR_NO_IR);
    close_attr(f);close_attr(freqs);close_attr(band);close_attr(bands_at);
    parse((void *)fixture,used);
}
int main(void) {
    make_fixture(1,0,0,5745);assert(ap && channel && got_types && got_bands);
    make_fixture(0,0,0,5745);assert(!ap && channel);
    make_fixture(1,1,0,5745);assert(ap && !channel);
    make_fixture(1,0,1,5745);assert(ap && !channel);
    make_fixture(1,0,0,2412);assert(ap && !channel);
    /* Malformed/truncated nested attributes never manufacture capability. */
    for(int n=0;n<64;n++) {
        memset(fixture,0,sizeof(fixture)); used=ap=channel=got_types=got_bands=0;
        fixture[0]=(unsigned char)n; fixture[2]=NL80211_ATTR_WIPHY_BANDS;
        parse((void *)fixture,n>0?n-1:0); assert(!ap && !channel);
    }
    puts("AP parser: capability, regulatory restriction and malformed data checks passed");
    return 0;
}
