/* SPDX-License-Identifier: MIT-0
 * Read-only nl80211 query. No interface, channel or regulatory changes.
 * Only fixed capability flags leave this program; no addresses or names.
 */
#include <sys/socket.h>
#include <sys/time.h>
#include <linux/netlink.h>
#include <linux/genetlink.h>
#include <linux/nl80211.h>
#include <net/if.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#define STEP(n) (((n)+3)&~3)
static unsigned char buffer[65536];
static int ap, channel, got_types, got_bands;
static int valid(const struct nlattr *a, int n) {
    return n >= (int)sizeof(*a) && a->nla_len >= sizeof(*a) && a->nla_len <= n;
}
static uint32_t number(const struct nlattr *a) {
    uint32_t v=0;
    if(a->nla_len >= sizeof(*a)+sizeof(v)) memcpy(&v,a+1,sizeof(v));
    return v;
}
static void frequency(struct nlattr *a, int n) {
    int disabled=0, no_ir=0; uint32_t freq=0;
    for(;valid(a,n);n-=STEP(a->nla_len),a=(void *)((char *)a+STEP(a->nla_len))) {
        switch(a->nla_type & NLA_TYPE_MASK) {
        case NL80211_FREQUENCY_ATTR_FREQ: freq=number(a); break;
        case NL80211_FREQUENCY_ATTR_DISABLED: disabled=1; break;
        case NL80211_FREQUENCY_ATTR_NO_IR: no_ir=1; break;
        }
    }
    if(freq==5745 && !disabled && !no_ir) channel=1;
}
static void bands(struct nlattr *a, int n) {
    for(;valid(a,n);n-=STEP(a->nla_len),a=(void *)((char *)a+STEP(a->nla_len))) {
        struct nlattr *b=(void *)(a+1); int m=a->nla_len-sizeof(*a);
        for(;valid(b,m);m-=STEP(b->nla_len),b=(void *)((char *)b+STEP(b->nla_len))) {
            if((b->nla_type & NLA_TYPE_MASK)!=NL80211_BAND_ATTR_FREQS) continue;
            struct nlattr *f=(void *)(b+1); int l=b->nla_len-sizeof(*b);
            for(;valid(f,l);l-=STEP(f->nla_len),f=(void *)((char *)f+STEP(f->nla_len)))
                frequency((void *)(f+1),f->nla_len-sizeof(*f));
        }
    }
}
static void parse(struct nlattr *a, int n) {
    for(;valid(a,n);n-=STEP(a->nla_len),a=(void *)((char *)a+STEP(a->nla_len))) {
        int type=a->nla_type & NLA_TYPE_MASK;
        if(type==NL80211_ATTR_SUPPORTED_IFTYPES) {
            struct nlattr *b=(void *)(a+1); int m=a->nla_len-sizeof(*a);
            got_types=1;
            for(;valid(b,m);m-=STEP(b->nla_len),b=(void *)((char *)b+STEP(b->nla_len)))
                if((b->nla_type & NLA_TYPE_MASK)==NL80211_IFTYPE_AP) ap=1;
        } else if(type==NL80211_ATTR_WIPHY_BANDS) {
            got_bands=1; bands((void *)(a+1),a->nla_len-sizeof(*a));
        }
    }
}
static int request(int fd, int family, int cmd, int attr, const void *data, int size, int seq) {
    unsigned char msg[256]={0};
    struct nlmsghdr *h=(void *)msg;
    struct genlmsghdr *g=(void *)(h+1);
    struct nlattr *a=(void *)(g+1);
    struct sockaddr_nl dest={.nl_family=AF_NETLINK};
    if(size>128) return -1;
    h->nlmsg_len=NLMSG_LENGTH(GENL_HDRLEN)+STEP(sizeof(*a)+size);
    h->nlmsg_type=family; h->nlmsg_flags=NLM_F_REQUEST; h->nlmsg_seq=seq;
    g->cmd=cmd; g->version=1; a->nla_type=attr; a->nla_len=sizeof(*a)+size;
    memcpy(a+1,data,size);
    return sendto(fd,msg,h->nlmsg_len,0,(void *)&dest,sizeof(dest));
}
static int receive(int fd, int family, int seq) {
    struct sockaddr_nl sender; socklen_t len=sizeof(sender);
    int size=recvfrom(fd,buffer,sizeof(buffer),0,(void *)&sender,&len);
    if(size<=0 || sender.nl_pid!=0) return -1;
    struct nlmsghdr *h=(void *)buffer;
    int result=0;
    for(;NLMSG_OK(h,(unsigned)size);h=NLMSG_NEXT(h,size)) {
        if(h->nlmsg_seq!=(unsigned)seq) continue;
        if(h->nlmsg_type==NLMSG_ERROR) return -1;
        if(h->nlmsg_type!=family || h->nlmsg_len<NLMSG_LENGTH(GENL_HDRLEN)) continue;
        struct nlattr *a=(void *)((char *)NLMSG_DATA(h)+GENL_HDRLEN);
        int n=h->nlmsg_len-NLMSG_LENGTH(GENL_HDRLEN);
        if(family==GENL_ID_CTRL) {
            for(;valid(a,n);n-=STEP(a->nla_len),a=(void *)((char *)a+STEP(a->nla_len)))
                if((a->nla_type & NLA_TYPE_MASK)==CTRL_ATTR_FAMILY_ID && a->nla_len>=sizeof(*a)+2) {
                    uint16_t id; memcpy(&id,a+1,2); result=id;
                }
        } else { parse(a,n); result=1; }
    }
    return result;
}
int main(int argc,char **argv) {
    struct sockaddr_nl local={.nl_family=AF_NETLINK};
    struct timeval timeout={.tv_sec=2};
    if(argc!=2) return 2;
    unsigned index=if_nametoindex(argv[1]);
    if(!index) goto unknown;
    int fd=socket(AF_NETLINK,SOCK_RAW,NETLINK_GENERIC);
    if(fd<0) goto unknown;
    setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    if(bind(fd,(void *)&local,sizeof(local))<0) {close(fd);goto unknown;}
    int family=-1;
    if(request(fd,GENL_ID_CTRL,CTRL_CMD_GETFAMILY,CTRL_ATTR_FAMILY_NAME,"nl80211",8,1)>=0)
        family=receive(fd,GENL_ID_CTRL,1);
    if(family<=0 || request(fd,family,NL80211_CMD_GET_WIPHY,NL80211_ATTR_IFINDEX,&index,sizeof(index),2)<0 || receive(fd,family,2)<0) {
        close(fd); goto unknown;
    }
    close(fd);
    if(!got_types || !got_bands) goto unknown;
    printf("ap_capable=%s\nchannel149_allowed=%s\n",ap?"yes":"no",channel?"yes":"no");
    return ap && channel ? 0:1;
unknown:
    puts("ap_capable=unknown\nchannel149_allowed=unknown"); return 2;
}
