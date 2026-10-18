import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { Profile, ProfileType } from 'proxy_core';
import { convertShareLinks, isShareLinkPayload, ShareLinkResult } from './ShareLinkParser';

export interface ProfileStoreData {
  profiles: Profile[];
  current: string;
}

const MAX_CONFIG_SIZE = 10 * 1024 * 1024;

/** 配置文件与元数据仓库。配置本体保存在 filesDir/profiles/{uid}.yaml，供 Go 内核直接读取。 */
export class ProfileRepository {
  private context: common.Context;
  private profilesDir: string;
  private indexPath: string;

  constructor(context: common.Context) {
    this.context = context;
    this.profilesDir = `${context.filesDir}/profiles`;
    this.indexPath = `${this.profilesDir}/index.json`;
  }

  async list(): Promise<ProfileStoreData> {
    await this.ensureDirectory();
    if (!(await this.exists(this.indexPath))) {
      return { profiles: [], current: '' };
    }
    try {
      const content = await fileIo.readText(this.indexPath);
      const store = JSON.parse(content) as ProfileStoreData;
      // 旧版本允许“有配置但没有当前配置”，这会让首页和代理页看起来像导入失败。
      // 自动选择第一个有效配置，同时修复已被删除的 current 指针。
      if (store.profiles.length > 0 &&
        !store.profiles.some((profile: Profile) => profile.uid === store.current)) {
        store.current = store.profiles[0].uid;
        await this.saveIndex(store);
      }
      return store;
    } catch (error) {
      console.error('[ProfileRepository] 读取索引失败: ' + (error as Error).message);
      return { profiles: [], current: '' };
    }
  }

  async importFromUrl(url: string): Promise<Profile> {
    this.ensureHttpUrl(url);
    const content = await this.download(url);
    const uid = this.newUid();
    const profile: Profile = {
      uid,
      type: ProfileType.Remote,
      name: this.nameFromUrl(url),
      file: `${uid}.yaml`,
      url,
      updated: Date.now()
    };
    await this.saveNewProfile(profile, content);
    return profile;
  }

  /**
   * 从分享链接导入（ss / vmess / vless / trojan / hysteria2 / tuic）。
   * 链接本身不含订阅地址，转换出的 YAML 按本地配置保存。
   */
  async importFromShareLinks(raw: string): Promise<Profile> {
    const result: ShareLinkResult = convertShareLinks(raw);
    const uid = this.newUid();
    const profile: Profile = {
      uid,
      type: ProfileType.Local,
      name: this.nameFromShareLinks(result),
      file: `${uid}.yaml`,
      desc: `分享链接导入 · ${result.count} 个节点`,
      updated: Date.now()
    };
    await this.saveNewProfile(profile, result.yaml);
    return profile;
  }

  async importFromFile(uri: string): Promise<Profile> {
    await this.ensureDirectory();
    const uid = this.newUid();
    const destination = this.profilePath(uid);
    let source: fileIo.File | undefined = undefined;
    try {
      source = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      await fileIo.copyFile(source.fd, destination);
    } catch (error) {
      throw new Error('读取配置文件失败: ' + (error as Error).message);
    } finally {
      if (source) {
        await this.closeFile(source);
      }
    }

    try {
      const stat = await fileIo.stat(destination);
      if (stat.size > MAX_CONFIG_SIZE) {
        throw new Error('配置文件不能超过 10 MB');
      }
      const content = await fileIo.readText(destination);
      const normalized = this.normalizeSubscription(content);
      if (normalized !== content) {
        await this.writeText(destination, normalized);
      }
      const profile: Profile = {
        uid,
        type: ProfileType.Local,
        name: this.nameFromUri(uri),
        file: `${uid}.yaml`,
        updated: Date.now()
      };
      const store = await this.list();
      store.profiles.push(profile);
      if (store.current.length === 0) {
        store.current = profile.uid;
      }
      await this.saveIndex(store);
      return profile;
    } catch (error) {
      if (await this.exists(destination)) {
        try {
          await fileIo.unlink(destination);
        } catch (unlinkError) {
          console.warn('[ProfileRepository] 清理无效配置失败: ' + (unlinkError as Error).message);
        }
      }
      throw new Error((error as Error).message);
    }
  }

  async update(profile: Profile): Promise<Profile> {
    if (profile.type !== ProfileType.Remote || !profile.url) {
      throw new Error('本地配置不支持在线更新');
    }
    const content = await this.download(profile.url);
    await this.writeText(this.profilePath(profile.uid), content);
    const updated: Profile = {
      uid: profile.uid,
      type: profile.type,
      name: profile.name,
      desc: profile.desc,
      file: profile.file,
      url: profile.url,
      updated: Date.now(),
      extra: profile.extra,
      proxySelected: profile.proxySelected
    };
    const store = await this.list();
    store.profiles = store.profiles.map((item: Profile) => item.uid === profile.uid ? updated : item);
    await this.saveIndex(store);
    return updated;
  }

  async setCurrent(uid: string): Promise<void> {
    const store = await this.list();
    if (!store.profiles.some((profile: Profile) => profile.uid === uid)) {
      throw new Error('配置不存在');
    }
    store.current = uid;
    await this.saveIndex(store);
  }

  /** 编辑配置元数据。远程配置可同时修改订阅地址，本地配置只修改名称与备注。 */
  async updateMetadata(uid: string, name: string, url: string, desc: string): Promise<Profile> {
    const normalizedName = name.trim();
    const normalizedUrl = url.trim();
    const normalizedDesc = desc.trim();
    if (normalizedName.length === 0) {
      throw new Error('配置名称不能为空');
    }
    if (normalizedName.length > 80) {
      throw new Error('配置名称不能超过 80 个字符');
    }
    if (normalizedDesc.length > 500) {
      throw new Error('备注不能超过 500 个字符');
    }

    const store = await this.list();
    const profile = store.profiles.find((item: Profile) => item.uid === uid);
    if (!profile) {
      throw new Error('配置不存在');
    }
    if (profile.type === ProfileType.Remote) {
      this.ensureHttpUrl(normalizedUrl);
    }

    const updated: Profile = {
      uid: profile.uid,
      type: profile.type,
      name: normalizedName,
      desc: normalizedDesc.length > 0 ? normalizedDesc : undefined,
      file: profile.file,
      url: profile.type === ProfileType.Remote ? normalizedUrl : profile.url,
      updated: profile.updated,
      extra: profile.extra,
      proxySelected: profile.proxySelected
    };
    store.profiles = store.profiles.map((item: Profile) => item.uid === uid ? updated : item);
    await this.saveIndex(store);
    return updated;
  }

  /** 保存某个配置中代理组的节点选择，防止重载配置时回到默认节点。 */
  async setProxySelection(uid: string, groupName: string, proxyName: string): Promise<void> {
    const store = await this.list();
    const profile = store.profiles.find((item: Profile) => item.uid === uid);
    if (!profile) {
      throw new Error('配置不存在');
    }
    const selected: Record<string, string> = profile.proxySelected ?? {};
    selected[groupName] = proxyName;
    profile.proxySelected = selected;
    await this.saveIndex(store);
  }

  async delete(profile: Profile): Promise<void> {
    const store = await this.list();
    store.profiles = store.profiles.filter((item: Profile) => item.uid !== profile.uid);
    if (store.current === profile.uid) {
      store.current = store.profiles.length > 0 ? store.profiles[0].uid : '';
    }
    const path = this.profilePath(profile.uid);
    if (await this.exists(path)) {
      try {
        await fileIo.unlink(path);
      } catch (error) {
        throw new Error('删除配置文件失败: ' + (error as Error).message);
      }
    }
    await this.saveIndex(store);
  }

  private async saveNewProfile(profile: Profile, content: string): Promise<void> {
    await this.ensureDirectory();
    await this.writeText(this.profilePath(profile.uid), content);
    const store = await this.list();
    store.profiles.push(profile);
    if (store.current.length === 0) {
      store.current = profile.uid;
    }
    await this.saveIndex(store);
  }

  private async download(url: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingCache: false,
        header: { 'User-Agent': 'ClashH/0.1.0' }
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error('服务器返回 HTTP ' + response.responseCode);
      }
      const content = String(response.result);
      return this.normalizeSubscription(content);
    } catch (error) {
      throw new Error('下载配置失败: ' + (error as Error).message);
    } finally {
      request.destroy();
    }
  }

  /** 订阅正文可能是 Clash YAML，也可能是（base64 编码的）分享链接列表，后者先转成 YAML。 */
  private normalizeSubscription(content: string): string {
    if (content.length === 0) {
      throw new Error('配置内容为空');
    }
    if (content.length > MAX_CONFIG_SIZE) {
      throw new Error('配置文件不能超过 10 MB');
    }
    if (isShareLinkPayload(content)) {
      return convertShareLinks(content).yaml;
    }
    this.validateConfigContent(content);
    return content;
  }

  private validateConfigContent(content: string): void {
    if (content.length === 0) {
      throw new Error('配置内容为空');
    }
    if (content.length > MAX_CONFIG_SIZE) {
      throw new Error('配置文件不能超过 10 MB');
    }
    const hasProxy = content.indexOf('proxies:') >= 0 || content.indexOf('proxy-providers:') >= 0 ||
      content.indexOf('proxy-groups:') >= 0;
    if (!hasProxy) {
      throw new Error('文件不是有效的 Clash/Mihomo YAML 配置');
    }
  }

  private ensureHttpUrl(url: string): void {
    const normalized = url.toLowerCase();
    if (!normalized.startsWith('https://') && !normalized.startsWith('http://')) {
      throw new Error('订阅地址必须使用 HTTP 或 HTTPS');
    }
  }

  private async ensureDirectory(): Promise<void> {
    if (!(await this.exists(this.profilesDir))) {
      try {
        await fileIo.mkdir(this.profilesDir, true);
      } catch (error) {
        throw new Error('创建配置目录失败: ' + (error as Error).message);
      }
    }
  }

  private async saveIndex(store: ProfileStoreData): Promise<void> {
    await this.writeText(this.indexPath, JSON.stringify(store));
  }

  private async writeText(path: string, content: string): Promise<void> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(path,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, content);
    } catch (error) {
      throw new Error('写入配置失败: ' + (error as Error).message);
    } finally {
      if (file) {
        await this.closeFile(file);
      }
    }
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (error) {
      return false;
    }
  }

  private async closeFile(file: fileIo.File): Promise<void> {
    try {
      await fileIo.close(file);
    } catch (error) {
      console.warn('[ProfileRepository] 关闭文件失败: ' + (error as Error).message);
    }
  }

  private profilePath(uid: string): string {
    return `${this.profilesDir}/${uid}.yaml`;
  }

  private newUid(): string {
    return `${Date.now()}-${Math.floor(Math.random() * 1000000)}`;
  }

  private nameFromUrl(url: string): string {
    const withoutScheme = url.replace(/^https?:\/\//i, '');
    const host = withoutScheme.split('/')[0];
    return host.length > 0 ? host : '远程配置';
  }

  private nameFromShareLinks(result: ShareLinkResult): string {
    if (result.count === 1 && result.firstName.length > 0) {
      return result.firstName;
    }
    return result.firstName.length > 0 ? `${result.firstName} 等 ${result.count} 个节点` : '分享链接配置';
  }

  private nameFromUri(uri: string): string {
    const encoded = uri.substring(uri.lastIndexOf('/') + 1);
    try {
      const decoded = decodeURIComponent(encoded);
      return decoded.length > 0 ? decoded : '本地配置';
    } catch (error) {
      return encoded.length > 0 ? encoded : '本地配置';
    }
  }
}
